# dinie

Official Ruby SDK for the [Dinie](https://dinie.com.br) V3 API (backend-only).

A hand-written, synchronous Ruby client for the Dinie credit-as-a-service platform: OAuth2
client-credentials auth (handled for you), automatic retries with idempotency, cursor pagination,
typed errors, and webhook verification. Snake_case throughout — the wire and the Ruby surface match,
so there is no casing to translate.

> **Status — pre-release (`0.0.1`).** The public surface is frozen against the Dinie V3 contract.
> RubyGems publishing is planned for V1.0; until then `dinie` is a private gem.

## Requirements

- Ruby >= 3.1
- A Dinie API credential (`client_id` + `client_secret`)

## Installation

```ruby
# Gemfile (once published)
gem "dinie"
```

```bash
bundle install
```

The SDK depends on `faraday` (with the `net-http-persistent` adapter for a real connection pool)
and `faraday-multipart`. Both are pulled in automatically.

## Quickstart

```ruby
require "dinie"

client = Dinie::Client.new(client_id: "dinie_ci_…", client_secret: "…")

customer = client.customers.create(
  email: "ana@example.com",
  phone: "+5511999999999",
  cpf: "123.456.789-09",
  cnpj: "12.345.678/0001-95"
)

customer.id      # => "cust_…"
customer.status  # => "pending_kyc"
```

The client owns a connection pool and an in-memory OAuth2 token cache, so **construct it once and
reuse it**. Tokens are fetched and refreshed transparently — you never call the token endpoint
yourself.

### Configuration

Pass options to the constructor, or let the SDK read them from the environment.

```ruby
client = Dinie::Client.new(
  client_id:     "dinie_ci_…",   # or ENV["DINIE_CLIENT_ID"]
  client_secret: "…",            # or ENV["DINIE_CLIENT_SECRET"]
  base_url:      nil,            # or ENV["DINIE_BASE_URL"]; default https://api.dinie.com.br/api/v3
  timeout:       30,            # per-request timeout, in SECONDS
  max_retries:   3,            # retries after the first attempt
  idempotency:   true,        # auto X-Idempotency-Key on POST/PATCH
  log_level:     :off         # :off | :error | :warn | :info | :debug (or ENV["DINIE_LOG"])
)
```

| Variable             | Used for                                                       |
| -------------------- | -------------------------------------------------------------- |
| `DINIE_CLIENT_ID`    | OAuth2 client id (when `client_id:` is omitted)                |
| `DINIE_CLIENT_SECRET`| OAuth2 client secret (when `client_secret:` is omitted)        |
| `DINIE_BASE_URL`     | API base URL incl. `/api/v3` (when `base_url:` is omitted)     |
| `DINIE_LOG`          | log level (when `log_level:` is omitted)                       |

Need a one-off override (a tighter timeout for a single call path)? Clone the client — the clone
**shares the same token cache and connection pool**, so it never triggers a re-auth:

```ruby
fast = client.with_options(timeout: 5)
```

Logging is opt-in and redacts credentials and PII (`authorization`, `cpf`, `cnpj`, `client_secret`,
`phone`, …) before anything is written.

## End-to-end flow: Customer → Credit Offer → Loan

The credit lifecycle is: register a customer, let Dinie run KYC and underwriting (you are notified by
webhook — see below), then read the resulting **credit offer**, **simulate** it, and **contract** a
loan from the accepted simulation.

```ruby
client = Dinie::Client.new(client_id: ENV["DINIE_CLIENT_ID"], client_secret: ENV["DINIE_CLIENT_SECRET"])

# 1. Register the customer.
customer = client.customers.create(
  email: "ana@example.com",
  phone: "+5511999999999",
  cpf:   "123.456.789-09",
  cnpj:  "12.345.678/0001-95"
)

# 2. Dinie runs KYC + underwriting. When the customer is approved, a `credit_offer.available`
#    webhook fires. Read the offers (they are NOT created by you):
offer = client.customers.credit_offers.list(customer.id).first
# …or fetch a known offer directly:
offer = client.credit_offers.retrieve("co_…")

offer.approved_amount        # => 25000.0  (Money — a Float, BRL)
offer.monthly_interest_rate  # => 4.5

# 3. Simulate the offer for the amount and term the customer wants.
simulation = client.credit_offers.create_simulation(
  offer.id,
  requested_amount:  25_000.0,
  installment_count: 12
)

simulation.installment_amount  # => 2_343.21
simulation.total_amount        # => 28_118.52

# 4. Contract the loan from the accepted simulation.
loan = client.loans.create(
  credit_offer_id:    offer.id,
  simulation_id:      simulation.id,
  installment_count:  simulation.installment_count,
  installment_amount: simulation.installment_amount,
  first_due_date:     "2026-07-10"  # ISO-8601 date
)

loan.id          # => "ln_…"
loan.status      # => "awaiting_signatures"
loan.signing_url # => CCB signature URL (present while awaiting signatures)

# Later, inspect the amortization schedule:
client.loans.transactions.list(loan.id).each do |installment|
  puts "#{installment.due_date}: #{installment.amount_due} (#{installment.status})"
end
```

> **Note.** All monetary fields are `Money` — a plain `Float` in BRL. All timestamps
> (`created_at`, `valid_until`, …) are integer Unix epoch seconds; only `RateLimit#reset_at` is a
> `Time`. ID prefixes (`cust_`, `co_`, `sim_`, `ln_`, `tx_`) are documented on each field; the value
> itself is a `String`.

## Pagination

List endpoints return a `Dinie::Page` that auto-paginates by cursor. It does **not** load every page
eagerly — `#each` walks pages on demand, following `has_more` (never the page size).

```ruby
# Iterate every customer across all pages:
client.customers.list(limit: 50).each do |customer|
  puts customer.id
end

# Page-by-page, for manual control:
client.customers.list.each_page do |page|
  process(page.data)        # Array<Dinie::Customer>
  page.has_more             # => true / false
end

# Just the first N, fetched lazily (only as many pages as needed):
top = client.customers.list.first(10)
```

Without a block, `#each` and `#each_page` return an `Enumerator`, so `.map` / `.lazy` work too.

`client.banks.list` is the one exception: the bank directory is **not** paginated, so it returns a
flat `Array<Dinie::Bank>` in a single call.

## Webhooks

Dinie delivers events (Standard Webhooks v1, HMAC-SHA256). `Dinie::Webhooks.extract` verifies the
signature **and** the timestamp, then returns the typed event — or raises. It never returns an
unverified payload, and it needs no client (verification is just your signing secret).

```ruby
# In your Rack / Rails / Sinatra handler:
event = Dinie::Webhooks.extract(
  headers: request.headers.to_h,   # must include webhook-id / webhook-timestamp / webhook-signature
  body:    request.raw_post,       # the RAW body, before JSON parsing
  secret:  ENV["DINIE_WEBHOOK_SECRET"]  # "whsec_…" (or an Array of secrets during rotation)
)

case event
when Dinie::Events::CustomerActive
  activate_customer(event.data.id)
when Dinie::Events::CreditOfferAvailable
  notify_offer(event.data.customer_id, event.data.approved_amount)
when Dinie::Events::LoanActive
  release_funds(event.data.id)
when Dinie::Events::LoanPaymentReceived
  record_payment(event.data.id, event.data.payment.amount)
else
  Rails.logger.info("Unhandled Dinie event: #{event.type}")
end
```

Header lookup is case-insensitive and accepts string or symbol keys. The signed payload is
`"{webhook-id}.{webhook-timestamp}.{body}"`, the comparison is constant-time, and multiple
space-separated `v1,<sig>` signatures are accepted (so secret rotation works from either side).

Failures raise, so you can map them to HTTP responses:

| Raised                                | When                                                            |
| ------------------------------------- | --------------------------------------------------------------- |
| `Dinie::WebhookSignatureError`        | a header is missing, no secret matched, or the HMAC differs      |
| `Dinie::WebhookTimestampError`        | the timestamp is malformed or outside the ±300s window           |
| `Dinie::UnknownWebhookEventError`     | the signature is valid but the `type` is not in the SDK's catalog |

## Error handling

Every non-2xx response becomes a typed error. The hierarchy lets you rescue broadly or narrowly, and
each error carries the machine-readable `code` and the `request_id` for support tickets.

```ruby
begin
  client.credit_offers.retrieve("co_does_not_exist")
rescue Dinie::NotFoundError => e
  warn "Not found (#{e.code}) — request #{e.request_id}"
rescue Dinie::ValidationError => e
  warn "Invalid: #{e.detail}"          # RFC 9457 Problem Details
rescue Dinie::RateLimitError
  # transient — the SDK already retried with backoff; back off further if you see this
rescue Dinie::APIStatusError => e
  warn "API error #{e.status}: #{e.title}"
rescue Dinie::APIConnectionError
  # network/DNS/timeout — no response was received
end
```

```text
Dinie::Error
├── Dinie::APIError
│   ├── Dinie::APIConnectionError → Dinie::APITimeoutError
│   └── Dinie::APIStatusError
│       ├── Dinie::BadRequestError   (400)   Dinie::ConflictError    (409)
│       ├── Dinie::AuthError         (401)   Dinie::ValidationError  (422)
│       ├── Dinie::PermissionError   (403)   Dinie::RateLimitError   (429)
│       └── Dinie::NotFoundError     (404)   Dinie::ServerError      (500 + ≥500 fallback)
├── Dinie::OAuthError                        # token handshake failed
├── Dinie::WebhookSignatureError
├── Dinie::WebhookTimestampError
└── Dinie::UnknownWebhookEventError
```

Retries are automatic for `408/429/500/502/503/504` and transport errors (exponential backoff with
jitter, honoring `Retry-After` up to 60s). `409`/`410` are never retried. A stable
`X-Idempotency-Key` is minted once per logical write and reused across retries, so a retry never
creates a duplicate resource.

After any call you can read the latest rate-limit snapshot:

```ruby
rl = client.rate_limit            # => Dinie::RateLimit or nil
rl&.remaining                     # => 87
rl&.reset_at                      # => 2026-06-02 12:00:30 UTC (a Time)
```

## Types

The full public surface is mirrored as RBS signatures under [`sig/`](sig/) — install the gem and
point [Steep](https://github.com/soutaro/steep) or Solargraph at it for static type checking and
editor hover. YARD documentation covers every public class and method.

## Development

```bash
bundle install
bundle exec rspec        # tests — WebMock, zero network
bundle exec rubocop      # lint
bundle exec steep check  # type check (informative in v1 — see Steepfile)
bundle exec yard doc     # build the API docs
```

## License

[MIT](LICENSE) © Dinie

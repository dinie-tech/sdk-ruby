# frozen_string_literal: true

require "faraday"
require "faraday/net_http_persistent"

module Dinie
  # `Dinie::Client` — the SDK entry point (architecture §2 RB1, §3.2, §10), porting `sdk-js`
  # `src/generated/client.ts`. The client is **`Dinie::Client`**, not `Dinie`, because the `Dinie`
  # module already owns the namespace (RB1). Construct it once and reuse it: it owns a connection
  # pool and an in-memory OAuth2 token cache.
  #
  # Responsibilities:
  #   1. **Resolve credentials + base URL** — fall back to `DINIE_CLIENT_ID` / `DINIE_CLIENT_SECRET`
  #      / `DINIE_BASE_URL` when the matching argument is absent (architecture §3.2).
  #   2. **Build ONE shared `Faraday::Connection`** and inject it into BOTH the {Internal::HttpClient}
  #      and the {Internal::TokenManager}, so the token POST rides the SAME connection pool as every
  #      other request (architecture §10). This is also where story 005 mounts the logging
  #      middleware — see {#build_connection}.
  #   3. **Compose transport + auth** — build the real, concurrency-safe {Internal::TokenManager}
  #      (story 004) and the {Internal::HttpClient} on that shared connection. Resources hang off the
  #      same `@http` in later stories (007–015); this version wires the transport + auth core only.
  #   4. **`#with_options`** — clone the client with merged config, **sharing the same TokenManager
  #      and connection** so a per-call override (e.g. `timeout`) never triggers a re-auth
  #      (architecture §12, §21.4 — recommendation confirmed: yes).
  #
  # ── runtime ↔ generated boundary ──
  # Lives in `generated/`. Imports only from `runtime/` (the transport, token manager, error base);
  # never the reverse. Hand-authored in V0.3, regenerated in V0.5.
  #
  # @example
  #   client = Dinie::Client.new(client_id: id, client_secret: secret)
  #   fast   = client.with_options(timeout: 5) # shares the token cache — no re-auth
  class Client
    # Default per-request timeout, in SECONDS (RB17 — Faraday idiom).
    DEFAULT_TIMEOUT_SECONDS = Internal::HttpClient::DEFAULT_TIMEOUT_SECONDS
    # Default retry budget after the first attempt.
    DEFAULT_MAX_RETRIES = Internal::HttpClient::DEFAULT_MAX_RETRIES

    # @param client_id [String, nil] OAuth2 client id (falls back to `DINIE_CLIENT_ID`)
    # @param client_secret [String, nil] OAuth2 client secret (falls back to `DINIE_CLIENT_SECRET`)
    # @param base_url [String, nil] API base URL incl. `/api/v3` (falls back to `DINIE_BASE_URL`,
    #   then {Internal::HttpClient::DEFAULT_BASE_URL})
    # @param timeout [Numeric] per-request timeout in seconds (default {DEFAULT_TIMEOUT_SECONDS})
    # @param max_retries [Integer] retry budget after the first attempt (default {DEFAULT_MAX_RETRIES})
    # @param idempotency [Boolean] auto-generate `X-Idempotency-Key` on POST/PATCH (default true)
    # @param log_level [Symbol] logging level (story 005 wires the middleware; held here meanwhile)
    # @param logger [Object, nil] custom logger (story 005)
    # @param adapter [Symbol, nil] Faraday adapter (default `:net_http_persistent`)
    # @param token_manager [Internal::TokenManager, nil] shared manager (internal — `#with_options`
    #   passes the existing instance so the clone reuses the token cache; do not pass directly)
    # @param connection [Faraday::Connection, nil] shared connection (internal — `#with_options`
    #   passes the existing instance so the clone reuses the pool; do not pass directly)
    # @raise [Dinie::Error] when no client id/secret is resolvable and none is shared in
    def initialize(client_id: nil, client_secret: nil, base_url: nil, timeout: DEFAULT_TIMEOUT_SECONDS,
                   max_retries: DEFAULT_MAX_RETRIES, idempotency: true, log_level: :off, logger: nil,
                   adapter: nil, token_manager: nil, connection: nil)
      @base_url = first_present(base_url, ENV.fetch("DINIE_BASE_URL", nil)) || Internal::HttpClient::DEFAULT_BASE_URL
      # Carry the rebuildable options so `#with_options` can re-construct a clone with merged config.
      # Credentials are intentionally NOT stored here: the clone reuses the shared token manager.
      @options = {
        timeout: timeout, max_retries: max_retries, idempotency: idempotency,
        log_level: log_level, logger: logger, adapter: adapter
      }

      @connection = connection || build_connection(log_level: log_level, logger: logger, adapter: adapter)
      @token_manager = token_manager || build_token_manager(client_id, client_secret)
      @http = Internal::HttpClient.new(
        token_manager: @token_manager, base_url: @base_url, timeout: timeout,
        max_retries: max_retries, idempotency: idempotency, connection: @connection
      )
      # Resources hang off the shared `@http`; each is memoized on first access (stories 007–010).
    end

    # The customers resource — customers + KYC + bank-account + biometrics + the customer
    # credit-offers subresource (story 007).
    #
    # @return [Dinie::Resources::Customers]
    def customers
      @customers ||= Resources::Customers.new(@http)
    end

    # The latest rate-limit snapshot from the most recent response; `nil` before the first call.
    #
    # @return [Dinie::RateLimit, nil]
    def rate_limit
      @http.rate_limit
    end

    # Clone the client with merged config, **sharing the same TokenManager and connection** so a
    # per-call config override never forces a re-auth (architecture §12, §21.4). The merged options
    # (e.g. a smaller `timeout`) apply to the clone's HttpClient; the original is untouched.
    #
    # @param overrides [Hash] config overrides merged over this client's options (e.g. `timeout: 5`)
    # @return [Dinie::Client] a new client sharing this one's token cache + connection pool
    def with_options(**overrides)
      self.class.new(
        base_url: @base_url, token_manager: @token_manager, connection: @connection,
        **@options.merge(overrides)
      )
    end

    # The credit-offers resource — offers and simulations (architecture §3.2, story 008). Memoized
    # over the shared `@http`.
    #
    # @return [Dinie::Resources::CreditOffers]
    def credit_offers
      @credit_offers ||= Resources::CreditOffers.new(@http)
    end

    # The loans resource — loans and their transactions (architecture §3.2, story 008). Memoized
    # over the shared `@http`.
    #
    # @return [Dinie::Resources::Loans]
    def loans
      @loans ||= Resources::Loans.new(@http)
    end

    # The banks resource — the bank directory (architecture §3.2, §11, story 010). `banks.list`
    # returns a flat `Array<Bank>` (not paginated). Memoized over the shared `@http`.
    #
    # @return [Dinie::Resources::Banks]
    def banks
      @banks ||= Resources::Banks.new(@http)
    end

    # The credentials resource — API-key management (`dinie_ci_…`) (architecture §3.2, story 010).
    # Memoized over the shared `@http`.
    #
    # @return [Dinie::Resources::Credentials]
    def credentials
      @credentials ||= Resources::Credentials.new(@http)
    end

    # The webhook-endpoints resource — REST management of webhook endpoints (`we_…`) (architecture
    # §3.2, story 010). DISTINCT from event reception (`Dinie::Webhooks.extract`, story 011).
    # Memoized over the shared `@http`.
    #
    # @return [Dinie::Resources::WebhookEndpoints]
    def webhook_endpoints
      @webhook_endpoints ||= Resources::WebhookEndpoints.new(@http)
    end

    private

    # Build the real, concurrency-safe token manager (story 004) on the shared connection, raising
    # a clear {Dinie::Error} when no credentials are resolvable.
    def build_token_manager(client_id, client_secret)
      resolved_id = first_present(client_id, ENV.fetch("DINIE_CLIENT_ID", nil))
      resolved_secret = first_present(client_secret, ENV.fetch("DINIE_CLIENT_SECRET", nil))
      raise Dinie::Error, "Missing Dinie client id: pass `client_id:` or set DINIE_CLIENT_ID." if resolved_id.nil?
      if resolved_secret.nil?
        raise Dinie::Error, "Missing Dinie client secret: pass `client_secret:` or set DINIE_CLIENT_SECRET."
      end

      Internal::TokenManager.new(
        client_id: resolved_id, client_secret: resolved_secret,
        base_url: @base_url, connection: @connection
      )
    end

    # Build the ONE shared `Faraday::Connection` for this client. The HttpClient and the
    # TokenManager both ride it, so they share a single connection pool (architecture §10).
    #
    # The logging middleware (story 005) is mounted HERE, inside this block, BEFORE the adapter, so
    # it observes the FINAL request/response of EVERY call — including the TokenManager's
    # `POST /auth/token`, whose `Authorization: Basic` header carries the client secret and is
    # redacted by the middleware. It reads the `log_level:` / `logger:` captured by this method.
    #
    # The middleware is NOT mounted in {Internal::HttpClient#build_connection}: that builder is the
    # standalone fallback the composed client never uses; THIS shared connection is the one every
    # request (resource calls AND the token POST) actually rides.
    def build_connection(log_level:, logger:, adapter:)
      Faraday.new(url: @base_url) do |faraday|
        faraday.use Internal::Middleware::Logging, level: log_level, logger: logger
        faraday.adapter(adapter || :net_http_persistent)
      end
    end

    # First non-nil, non-empty string among the candidates, else `nil`.
    def first_present(*candidates)
      candidates.find { |value| !value.nil? && value != "" }
    end
  end
end

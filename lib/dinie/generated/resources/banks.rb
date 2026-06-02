# frozen_string_literal: true

require_relative "../types/bank"

module Dinie
  module Resources
    # `Dinie::Resources::Banks` — the `client.banks` resource: the bank directory (architecture
    # §3.2, §11). Ports `sdk-js` `src/generated/resources/banks.ts`. Copies the resource pattern
    # established by the {Dinie::Resources::Customers} exemplar (story 007). Hand-authored in V0.3,
    # regenerated in V0.5.
    #
    # ── Surface (frozen-surface.md) ──
    #   * `list(request_options:)` → **`Array<Bank>`** (FLAT — NOT paginated; see below)
    #
    # ── `/banks` does NOT paginate — the determinism rule (architecture §11) ──
    # Read against the contract (SoT): the `GET /banks` `200` response schema is `{ data: Bank[] }`
    # with ONLY `data` required — NO `has_more`, NO `object: 'list'`, and the operation declares NO
    # query params. The §11 rule is: a list is paginated **iff** its envelope carries `has_more`
    # (`Dinie::Page.paginated?(body)`). `/banks` has none, so `list` returns a flat `Array<Bank>` —
    # the full directory in one call, NOT a {Dinie::Page}. (Contrast `credentials.list` /
    # `webhook_endpoints.list`, whose envelopes DO carry `has_more`.) Because the contract defines
    # no query params, `list` takes only `request_options:` — there is no params object to thread.
    #
    # ── Idempotency ──
    # `list` is a GET → no `X-Idempotency-Key`.
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `generated/`. Holds the injected {Internal::HttpClient} and imports only the sibling
    # {Bank} type; never the reverse.
    #
    # @example
    #   banks = client.banks.list          # => Array<Dinie::Bank> (NOT a Page)
    #   banks.first.display_name           # => "001 - Banco do Brasil"
    class Banks
      # Path of the banks collection.
      BANKS_PATH = "/banks"

      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # List the banks available for customer bank-account submission (`GET /banks`). The response
      # is a flat `{ data: [...] }` envelope with NO `has_more` (architecture §11,
      # {Dinie::Page.paginated?} ⇒ false), so this returns a plain `Array<Bank>` — the full
      # directory in one call, NOT a paginated stream. Each entry is hydrated into a {Bank}.
      #
      # @param request_options [Hash] per-call overrides (timeout/headers/max_retries)
      # @return [Array<Dinie::Bank>] the full bank directory (a plain Array, NOT a {Dinie::Page})
      def list(request_options: {})
        body = @http.request(method: :get, path: BANKS_PATH, request_options:)
        body[:data].map { |raw| Bank.deserialize(raw) }
      end
    end
  end
end

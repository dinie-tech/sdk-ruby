# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/credit_offer"
require_relative "../types/simulation"

module Dinie
  module Resources
    # `Dinie::Resources::CreditOffers` — the `client.credit_offers` resource: the credit-offer
    # half of the credit flow (architecture §3.2). Ports `sdk-js`
    # `src/generated/resources/credit-offers.ts`. Copies the resource pattern established by the
    # {Dinie::Resources::Customers} exemplar (story 007). Hand-authored in V0.3, regenerated in V0.5.
    #
    # ── Surface (frozen-surface.md) ──
    #   * `list(limit:, starting_after:, **filters, request_options:)` → {Dinie::Page}<{CreditOffer}>
    #   * `retrieve(id, request_options:)`                              → {CreditOffer}
    #   * `create_simulation(credit_offer_id, **fields, request_options:)` → {Simulation}
    #
    # There is deliberately **NO `create`** (R10): credit offers are minted by the Core (the
    # `credit_offer.available` webhook), never POSTed — there is no `POST /credit-offers`. The
    # version-spec demo (`credit_offers.create`) is illustrative; the surface follows the openapi.
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `generated/`. Holds the injected {Internal::HttpClient} and imports only from
    # `runtime/` (the transport, the paginator) and sibling `generated/` types; never the reverse.
    #
    # @example
    #   offers = client.credit_offers.list(limit: 50)
    #   offers.each { |offer| puts offer.id }
    #   offer  = client.credit_offers.retrieve("co_…")
    #   sim    = client.credit_offers.create_simulation("co_…", requested_amount: 25_000.0, installment_count: 12)
    class CreditOffers
      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # List credit offers (`GET /credit-offers`), auto-paginating by `starting_after`. Optional
      # `**filters` (e.g. `customer_id:`, `status:`) pass through as query params; `limit` /
      # `starting_after` / each filter default to {Internal::OMIT} and are dropped when omitted.
      #
      # @param limit [Integer, Internal::OMIT] page size
      # @param starting_after [String, Internal::OMIT] cursor — a credit-offer id (`co_…`)
      # @param filters [Hash{Symbol => Object}] extra query filters passed through verbatim
      # @param request_options [Hash] per-call overrides (timeout/headers/idempotency_key/max_retries)
      # @return [Dinie::Page<Dinie::CreditOffer>]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after, **filters }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/credit-offers", query:, request_options:)
          { data: body[:data].map { |raw| CreditOffer.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Retrieve a single credit offer (`GET /credit-offers/{id}`).
      #
      # @param id [String] the credit-offer id (`co_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::CreditOffer]
      # @raise [Dinie::NotFoundError] when no offer has that id
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/credit-offers/#{id}", request_options:)
        CreditOffer.deserialize(raw)
      end

      # Price an offer (`POST /credit-offers/{id}/simulations`): dump the `CreateSimulationRequest`
      # and hydrate the returned {Simulation}. The parent id is the **1st positional argument**
      # (architecture §3.1); the body fields are idiomatic kwargs (RB4). The transport auto-carries
      # an `X-Idempotency-Key`. The method name keeps the verb-noun `create_simulation` verbatim
      # from the golden — a non-CRUD operation, NOT a generic `create` (the naming edge-case
      # mirrored from `createSimulation` in TS).
      #
      # @param credit_offer_id [String] the offer to simulate (`co_…`), 1st positional arg
      # @param fields [Hash{Symbol => Object}] `requested_amount:` (Float) + `installment_count:` (Integer)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Simulation]
      def create_simulation(credit_offer_id, request_options: {}, **fields)
        body = Simulation.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/credit-offers/#{credit_offer_id}/simulations", body:,
                            request_options:)
        Simulation.deserialize(raw)
      end
    end
  end
end

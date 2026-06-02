# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/loan"
require_relative "../types/transaction"

module Dinie
  module Resources
    # `Dinie::Resources::Loans` — the `client.loans` resource: the loan half of the credit flow
    # (architecture §3.2), plus the nested `loans.transactions` subresource (§3.1). Ports `sdk-js`
    # `src/generated/resources/loans.ts`. Copies the resource + subresource pattern established by
    # the {Dinie::Resources::Customers} exemplar (story 007). Hand-authored in V0.3, regenerated in
    # V0.5.
    #
    # ── Surface (frozen-surface.md) ──
    #   * `create(credit_offer_id:, simulation_id:, installment_count:, installment_amount:,
    #     first_due_date:, request_options:)`        → {Loan}
    #   * `retrieve(id, request_options:)`             → {Loan}
    #   * `transactions.list(loan_id, limit:, starting_after:, request_options:)`
    #                                                  → {Dinie::Page}<{Transaction}>
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `generated/`. Holds the injected {Internal::HttpClient} and imports only from
    # `runtime/` (transport, paginator) and sibling `generated/` types; never the reverse.
    #
    # @example
    #   loan = client.loans.create(
    #     credit_offer_id: "co_…", simulation_id: "sim_…",
    #     installment_count: 4, installment_amount: 7_997.34, first_due_date: "2026-04-03"
    #   )
    #   loan = client.loans.retrieve("ln_…")
    #   client.loans.transactions.list("ln_…").each { |tx| puts tx.id }
    class Loans
      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # Create a loan from an accepted credit-offer simulation (`POST /loans`). Dumps a
      # `CreateLoanRequest` (all five fields required — the partner chains the accepted simulation
      # back) and hydrates the returned {Loan}. The transport auto-carries an `X-Idempotency-Key`.
      #
      # @param credit_offer_id [String] the offer being contracted (`co_…`)
      # @param simulation_id [String] the accepted simulation (`sim_…`)
      # @param installment_count [Integer] the accepted number of installments (>= 1)
      # @param installment_amount [Float] the accepted installment amount
      # @param first_due_date [String] first installment due date (ISO-8601 date)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Loan]
      def create(credit_offer_id:, simulation_id:, installment_count:, installment_amount:,
                 first_due_date:, request_options: {})
        body = Loan.serialize_create(credit_offer_id:, first_due_date:, installment_amount:,
                                     installment_count:, simulation_id:)
        raw = @http.request(method: :post, path: "/loans", body:, request_options:)
        Loan.deserialize(raw)
      end

      # Retrieve a single loan (`GET /loans/{id}`).
      #
      # @param id [String] the loan id (`ln_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Loan]
      # @raise [Dinie::NotFoundError] when no loan has that id
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/loans/#{id}", request_options:)
        Loan.deserialize(raw)
      end

      # The loan transactions subresource (`loans.transactions`). Memoized so repeated access
      # returns one instance.
      #
      # @return [Dinie::Resources::Loans::Transactions]
      def transactions
        @transactions ||= Transactions.new(@http)
      end

      # `loans.transactions` — list a single loan's installments (architecture §3.1, §3.2). Holds
      # the same injected `@http`; `loan_id` is the **first positional argument** (the same shape as
      # `customers.credit_offers` in story 007).
      class Transactions
        # @param http [Dinie::Internal::HttpClient] the shared transport
        def initialize(http)
          @http = http
        end

        # List a loan's transactions (`GET /loans/{id}/transactions`), auto-paginating by
        # `starting_after`. `limit` / `starting_after` default to {Internal::OMIT} and are dropped
        # when omitted.
        #
        # @param loan_id [String] the parent loan id (`ln_…`) — first positional argument
        # @param limit [Integer, Internal::OMIT] page size
        # @param starting_after [String, Internal::OMIT] cursor — a transaction id (`tx_…`)
        # @param request_options [Hash] per-call overrides
        # @return [Dinie::Page<Dinie::Transaction>]
        def list(loan_id, limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
          path = "/loans/#{loan_id}/transactions"
          fetch_page = lambda do |cursor|
            query = { limit:, starting_after: cursor || starting_after }
                    .reject { |_key, value| Internal.omitted?(value) }
            body = @http.request(method: :get, path:, query:, request_options:)
            { data: body[:data].map { |raw| Transaction.deserialize(raw) }, has_more: body[:has_more] }
          end
          Dinie::Page.from_fetch(fetch_page)
        end
      end
    end
  end
end

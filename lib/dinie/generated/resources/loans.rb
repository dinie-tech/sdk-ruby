# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/loan"
require_relative "../types/transaction"

module Dinie
  module Resources
    class Loans
      def initialize(http)
        @http = http
      end

      def create(request_options: {}, **fields)
        body = Loan.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/loans", body:, request_options:)
        Loan.deserialize(raw)
      end

      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/loans/#{id}", request_options:)
        Loan.deserialize(raw)
      end

      def transactions
        @transactions ||= Transactions.new(@http)
      end

      class Transactions
        def initialize(http)
          @http = http
        end

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

# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/credit_offer"
require_relative "../types/simulation"

module Dinie
  module Resources
    class CreditOffers
      def initialize(http)
        @http = http
      end

      def create_simulation(id, request_options: {}, **fields)
        body = Simulation.serialize_create_simulation(**fields)
        raw = @http.request(method: :post, path: "/credit-offers/#{id}/simulations", body:, request_options:)
        Simulation.deserialize(raw)
      end

      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after, **filters }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/credit-offers", query:, request_options:)
          { data: body[:data].map { |raw| CreditOffer.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/credit-offers/#{id}", request_options:)
        CreditOffer.deserialize(raw)
      end
    end
  end
end

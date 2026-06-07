# frozen_string_literal: true

require_relative "../types/bank"

module Dinie
  module Resources
    class Banks
      def initialize(http)
        @http = http
      end

      def list(request_options: {})
        body = @http.request(method: :get, path: "/banks", request_options:)
        body[:data].map { |raw| Bank.deserialize(raw) }
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../types/bank"

module Dinie
  module Resources
    # Operations on the banks resource.
    class Banks
      def initialize(http)
        @http = http
      end

      # List banks
      #
      # List banks available for customer bank account submission.
      #
      # @param request_options [Hash] Request options.
      # @return [Object]
      def list(request_options: {})
        body = @http.request(method: :get, path: "/banks", request_options:)
        body[:data].map { |raw| Bank.deserialize(raw) }
      end
    end
  end
end

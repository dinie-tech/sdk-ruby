# frozen_string_literal: true

require_relative "../types/biometrics_session_exchange_response"

module Dinie
  module Resources
    class Biometrics
      def initialize(http)
        @http = http
      end

      def session_exchange(request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/biometrics/session-exchange", body:, request_options:)
        BiometricsSessionExchangeResponse.deserialize(raw)
      end
    end
  end
end

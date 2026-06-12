# frozen_string_literal: true

require_relative "../types/biometrics_session_exchange_response"

module Dinie
  module Resources
    # Operations on the biometrics resource.
    class Biometrics
      def initialize(http)
        @http = http
      end

      # Exchange a biometrics bootstrap code for a session token
      #
      # Internal endpoint — the kyc-app calls this with a credential that only has the `biometrics:exchange` scope, swapping the single-use bootstrap code (`dinie_bsc_…`) for a Token bound to the session's CreditLineApplication. The token is the bearer the wizard uses for every subsequent KYC request.
      #
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def session_exchange(request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/biometrics/session-exchange", body:, request_options:)
        BiometricsSessionExchangeResponse.deserialize(raw)
      end
    end
  end
end

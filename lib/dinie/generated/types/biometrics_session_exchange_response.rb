# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module BiometricsSessionExchangeResponseTokenType
    BEARER = "bearer"
    ALL = [BEARER].freeze
  end

  class BiometricsSessionExchangeResponse < Internal::Model
    attribute :access_token, :customer_id, :expires_in, :token_type

    def self.deserialize(raw)
      new(
        access_token: raw[:access_token],
        customer_id: raw[:customer_id],
        expires_in: raw[:expires_in],
        token_type: raw[:token_type]
      )
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanActiveData < Internal::Model
      attribute :id, :principal_amount, :requested_amount, :status

      def self.deserialize(raw)
        new(
          id: raw[:id],
          principal_amount: raw[:principal_amount],
          requested_amount: raw[:requested_amount],
          status: raw[:status]
        )
      end
    end

    class LoanActive < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanActiveData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.active"
        )
      end
    end
  end
end

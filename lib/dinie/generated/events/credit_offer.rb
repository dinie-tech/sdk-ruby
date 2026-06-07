# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class CreditOfferData < Internal::Model
      attribute :approved_amount, :customer_id, :due_date_rule, :external_id, :id, :installments, :min_amount,
                :monthly_interest_rate, :status, :valid_until

      def self.deserialize(raw)
        new(
          approved_amount: raw[:approved_amount],
          customer_id: raw[:customer_id],
          due_date_rule: raw[:due_date_rule],
          external_id: raw[:external_id],
          id: raw[:id],
          installments: raw[:installments],
          min_amount: raw[:min_amount],
          monthly_interest_rate: raw[:monthly_interest_rate],
          status: raw[:status],
          valid_until: raw[:valid_until]
        )
      end
    end

    class CreditOfferAvailable < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CreditOfferData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "credit_offer.available"
        )
      end
    end

    class CreditOfferExpired < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CreditOfferData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "credit_offer.expired"
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanCreatedData < Internal::Model
      attribute :credit_offer_id, :customer_id, :id, :installment_count, :requested_amount, :signing_url, :status

      def self.deserialize(raw)
        new(
          credit_offer_id: raw[:credit_offer_id],
          customer_id: raw[:customer_id],
          id: raw[:id],
          installment_count: raw[:installment_count],
          requested_amount: raw[:requested_amount],
          signing_url: raw[:signing_url],
          status: raw[:status]
        )
      end
    end

    class LoanCreated < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanCreatedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.created"
        )
      end
    end
  end
end

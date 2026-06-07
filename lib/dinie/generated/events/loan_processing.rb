# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanProcessingData < Internal::Model
      attribute :ccb_number, :credit_offer_id, :customer_id, :disbursement_method, :id, :status

      def self.deserialize(raw)
        new(
          ccb_number: raw[:ccb_number],
          credit_offer_id: raw[:credit_offer_id],
          customer_id: raw[:customer_id],
          disbursement_method: raw[:disbursement_method],
          id: raw[:id],
          status: raw[:status]
        )
      end
    end

    class LoanProcessing < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanProcessingData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.processing"
        )
      end
    end
  end
end

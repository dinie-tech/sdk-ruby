# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.processing` event (`WebhookEvent_LoanProcessing`) — architecture §3.1, §8. Fires when all
# required signatures are collected and disbursement is in progress. Hand-authored in V0.3; ports
# `sdk-js` `src/generated/events/loan-processing.ts` (@ `19c9bca`). DS-EVENT.
#
# `data` ({LoanProcessingData}) is the bespoke processing payload (`{id, credit_offer_id,
# customer_id, status, ccb_number, disbursement_method}`) — NOT the `Loan` read-model.
module Dinie
  module Events
    # Payload of a `loan.processing` event. `status` pinned to `processing`.
    class LoanProcessingData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :ccb_number, :credit_offer_id, :customer_id, :disbursement_method, :id, :status

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanProcessingData]
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

    # A verified `loan.processing` event (envelope + {LoanProcessingData}).
    class LoanProcessing < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanProcessing]
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

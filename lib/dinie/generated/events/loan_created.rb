# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.created` event (`WebhookEvent_LoanCreated`) — architecture §3.1, §8. Fires when the loan is
# created with the CCB generated synchronously; the loan starts in `awaiting_signatures`. Hand-
# authored in V0.3; ports `sdk-js` `src/generated/events/loan-created.ts` (@ `19c9bca`). DS-EVENT.
#
# `data` ({LoanCreatedData}) is the bespoke creation payload — NOT the 21-field `Dinie::Loan`
# read-model. `requested_amount` is a `Money` (`Float`, BRL).
module Dinie
  module Events
    # Payload of a `loan.created` event. `status` pinned to `awaiting_signatures`.
    class LoanCreatedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :credit_offer_id, :customer_id, :id, :installment_count, :requested_amount,
                :signing_url, :status

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanCreatedData]
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

    # A verified `loan.created` event (envelope + {LoanCreatedData}).
    class LoanCreated < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanCreated]
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

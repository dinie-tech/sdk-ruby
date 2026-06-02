# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.active` event (`WebhookEvent_LoanActive`) — architecture §3.1, §8. Fires when disbursement
# completes and the loan becomes active. Hand-authored in V0.3; ports `sdk-js`
# `src/generated/events/loan-active.ts` (@ `19c9bca`). DS-EVENT.
#
# `data` ({LoanActiveData}) is the bespoke active payload (`{id, status, requested_amount,
# principal_amount}`) — NOT the `Loan` read-model. Both amounts are `Money` (`Float`, BRL).
module Dinie
  module Events
    # Payload of a `loan.active` event. `status` pinned to `active`.
    class LoanActiveData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :id, :principal_amount, :requested_amount, :status

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanActiveData]
      def self.deserialize(raw)
        new(
          id: raw[:id],
          principal_amount: raw[:principal_amount],
          requested_amount: raw[:requested_amount],
          status: raw[:status]
        )
      end
    end

    # A verified `loan.active` event (envelope + {LoanActiveData}).
    class LoanActive < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanActive]
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

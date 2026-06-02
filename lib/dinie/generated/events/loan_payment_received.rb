# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.payment_received` event (`WebhookEvent_LoanPaymentReceived`) — architecture §3.1, §8. Fires
# when an installment payment is received. Hand-authored in V0.3; ports `sdk-js`
# `src/generated/events/loan-payment-received.ts` (@ `19c9bca`). DS-EVENT.
#
# `data` carries a NESTED `payment` object — hydrated by its own {LoanPayment.deserialize}. The
# contract @3fcfd83 carries NEITHER a `Loan` NOR a `Transaction` here: just `{id, status, payment:
# {amount, paid_at, installment_number}}`. So `Transaction.deserialize` is NOT reused.
# `payment.amount` is a `Money` (`Float`, BRL); `payment.paid_at` is `Integer` epoch (R-EPOCH).
module Dinie
  module Events
    # The payment captured for an installment (nested in {LoanPaymentReceivedData}).
    class LoanPayment < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :amount, :installment_number, :paid_at

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanPayment]
      def self.deserialize(raw)
        new(
          amount: raw[:amount],
          installment_number: raw[:installment_number],
          paid_at: raw[:paid_at]
        )
      end
    end

    # Payload of a `loan.payment_received` event. `status` pinned to `active`.
    class LoanPaymentReceivedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :id, :payment, :status

      # Hydrate the payload; the nested `payment` runs through {LoanPayment.deserialize}.
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanPaymentReceivedData]
      def self.deserialize(raw)
        new(
          id: raw[:id],
          payment: LoanPayment.deserialize(raw[:payment]),
          status: raw[:status]
        )
      end
    end

    # A verified `loan.payment_received` event (envelope + {LoanPaymentReceivedData}).
    class LoanPaymentReceived < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanPaymentReceived]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanPaymentReceivedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.payment_received"
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanPayment < Internal::Model
      attribute :amount, :installment_number, :paid_at

      def self.deserialize(raw)
        new(
          amount: raw[:amount],
          installment_number: raw[:installment_number],
          paid_at: raw[:paid_at]
        )
      end
    end

    class LoanPaymentReceivedData < Internal::Model
      attribute :id, :payment, :status

      def self.deserialize(raw)
        new(
          id: raw[:id],
          payment: LoanPayment.deserialize(raw[:payment]),
          status: raw[:status]
        )
      end
    end

    class LoanPaymentReceived < WebhookEventBase
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

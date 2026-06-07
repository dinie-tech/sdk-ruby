# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanError < Internal::Model
      attribute :code, :message

      def self.deserialize(raw)
        new(
          code: raw[:code],
          message: raw[:message]
        )
      end
    end

    class LoanStatusData < Internal::Model
      attribute :error, :id, :status

      def self.deserialize(raw)
        new(
          error: raw[:error] && LoanError.deserialize(raw[:error]),
          id: raw[:id],
          status: raw[:status]
        )
      end
    end

    class LoanCancelled < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.cancelled"
        )
      end
    end

    class LoanErrorEvent < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.error"
        )
      end
    end

    class LoanFinished < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.finished"
        )
      end
    end
  end
end

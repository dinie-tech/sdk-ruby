# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class CustomerStatusData < Internal::Model
      attribute :external_id, :id, :status

      def self.deserialize(raw)
        new(
          external_id: raw[:external_id],
          id: raw[:id],
          status: raw[:status]
        )
      end
    end

    class CustomerActive < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.active"
        )
      end
    end

    class CustomerUnderReview < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.under_review"
        )
      end
    end
  end
end

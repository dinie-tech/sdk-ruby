# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "../types/kyc"
require_relative "base"

module Dinie
  module Events
    class CustomerKycUpdatedData < Internal::Model
      attribute :external_id, :id, :kyc, :status

      def self.deserialize(raw)
        new(
          external_id: raw[:external_id],
          id: raw[:id],
          kyc: raw[:kyc].map { |requirement| Dinie.deserialize_kyc_requirement(requirement) },
          status: raw[:status]
        )
      end
    end

    class CustomerKycUpdated < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerKycUpdatedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.kyc_updated"
        )
      end
    end
  end
end

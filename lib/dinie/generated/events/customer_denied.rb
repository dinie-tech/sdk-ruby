# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class CustomerDeniedData < Internal::Model
      attribute :cnpj, :cpf, :email, :external_id, :id, :name, :phone, :status

      def self.deserialize(raw)
        new(
          cnpj: raw[:cnpj],
          cpf: raw[:cpf],
          email: raw[:email],
          external_id: raw[:external_id],
          id: raw[:id],
          name: raw[:name],
          phone: raw[:phone],
          status: raw[:status]
        )
      end
    end

    class CustomerDenied < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerDeniedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.denied"
        )
      end
    end
  end
end

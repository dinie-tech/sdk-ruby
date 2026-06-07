# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "../types/kyc"
require_relative "base"

module Dinie
  module Events
    class CustomerCreatedData < Internal::Model
      attribute :cnpj, :cpf, :email, :external_id, :id, :kyc, :name, :phone, :status, :trading_name

      def self.deserialize(raw)
        new(
          cnpj: raw[:cnpj],
          cpf: raw[:cpf],
          email: raw[:email],
          external_id: raw[:external_id],
          id: raw[:id],
          kyc: raw[:kyc].map { |requirement| Dinie.deserialize_kyc_requirement(requirement) },
          name: raw[:name],
          phone: raw[:phone],
          status: raw[:status],
          trading_name: raw[:trading_name]
        )
      end
    end

    class CustomerCreated < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerCreatedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.created"
        )
      end
    end
  end
end

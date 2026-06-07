# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "kyc"

module Dinie
  module CustomerStatus
    CREATING = "creating"
    PENDING_KYC = "pending_kyc"
    UNDER_REVIEW = "under_review"
    ACTIVE = "active"
    DENIED = "denied"
    ALL = [CREATING, PENDING_KYC, UNDER_REVIEW, ACTIVE, DENIED].freeze
  end

  class Customer < Internal::Model
    attribute :cnpj, :cpf, :created_at, :email, :external_id, :id, :kyc, :name, :phone, :status, :trading_name,
              :updated_at

    def self.deserialize(raw)
      new(
        cnpj: raw[:cnpj],
        cpf: raw[:cpf],
        created_at: raw[:created_at],
        email: raw[:email],
        external_id: raw[:external_id],
        id: raw[:id],
        kyc: raw[:kyc]&.map { |requirement| Dinie.deserialize_kyc_requirement(requirement) },
        name: raw[:name],
        phone: raw[:phone],
        status: raw[:status],
        trading_name: raw[:trading_name],
        updated_at: raw[:updated_at]
      )
    end

    def self.serialize_create(cnpj:, cpf:, email:, phone:, external_id: Internal::OMIT, name: Internal::OMIT)
      { cnpj:, cpf:, email:, external_id:, name:, phone: }.reject { |_key, value| Internal.omitted?(value) }
    end

    def self.serialize_update(email: Internal::OMIT, phone: Internal::OMIT)
      { email:, phone: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end
end

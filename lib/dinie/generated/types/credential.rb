# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module CredentialStatus
    ACTIVE = "active"
    REVOKED = "revoked"
    ALL = [ACTIVE, REVOKED].freeze
  end

  class Credential < Internal::Model
    attribute :client_id, :created_at, :expires_at, :id, :last_used_at, :name, :status, :updated_at

    def self.deserialize(raw)
      new(
        client_id: raw[:client_id],
        created_at: raw[:created_at],
        expires_at: raw[:expires_at],
        id: raw[:id],
        last_used_at: raw[:last_used_at],
        name: raw[:name],
        status: raw[:status],
        updated_at: raw[:updated_at]
      )
    end

    def self.serialize_create(name:, expires_at: Internal::OMIT)
      { expires_at:, name: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end

  class CredentialWithSecret < Credential
    attribute :client_secret

    def self.deserialize(raw)
      new(
        client_id: raw[:client_id],
        client_secret: raw[:client_secret],
        created_at: raw[:created_at],
        expires_at: raw[:expires_at],
        id: raw[:id],
        last_used_at: raw[:last_used_at],
        name: raw[:name],
        status: raw[:status],
        updated_at: raw[:updated_at]
      )
    end
  end
end

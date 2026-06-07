# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module WebhookEndpointStatus
    ACTIVE = "active"
    DISABLED = "disabled"
    ALL = [ACTIVE, DISABLED].freeze
  end

  class WebhookEndpoint < Internal::Model
    attribute :created_at, :description, :events, :id, :status, :updated_at, :url

    def self.deserialize(raw)
      new(
        created_at: raw[:created_at],
        description: raw[:description],
        events: raw[:events],
        id: raw[:id],
        status: raw[:status],
        updated_at: raw[:updated_at],
        url: raw[:url]
      )
    end

    def self.serialize_create(url:, description: Internal::OMIT, events: Internal::OMIT)
      { description:, events:, url: }.reject { |_key, value| Internal.omitted?(value) }
    end

    def self.serialize_update(description: Internal::OMIT, events: Internal::OMIT, status: Internal::OMIT, url: Internal::OMIT)
      { description:, events:, status:, url: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end

  class WebhookEndpointWithSecret < WebhookEndpoint
    attribute :secret

    def self.deserialize(raw)
      new(
        created_at: raw[:created_at],
        description: raw[:description],
        events: raw[:events],
        id: raw[:id],
        secret: raw[:secret],
        status: raw[:status],
        updated_at: raw[:updated_at],
        url: raw[:url]
      )
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class WebhookSecretRotation < Internal::Model
    attribute :id, :previous_secret_expires_at, :secret

    def self.deserialize(raw)
      new(
        id: raw[:id],
        previous_secret_expires_at: raw[:previous_secret_expires_at],
        secret: raw[:secret]
      )
    end
  end
end

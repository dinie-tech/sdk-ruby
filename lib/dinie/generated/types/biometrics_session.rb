# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class BiometricsSession < Internal::Model
    attribute :expires_at, :session_url

    def self.deserialize(raw)
      new(
        expires_at: raw[:expires_at],
        session_url: raw[:session_url]
      )
    end
  end
end

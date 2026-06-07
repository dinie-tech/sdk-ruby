# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module Events
    class WebhookEventBase < Internal::Model
      attribute :api_version, :created_at, :data, :delivery_id, :id, :timestamp, :type
    end
  end
end

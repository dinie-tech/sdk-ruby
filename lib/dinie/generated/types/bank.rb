# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class Bank < Internal::Model
    attribute :display_name, :id, :name

    def self.deserialize(raw)
      new(
        display_name: raw[:display_name],
        id: raw[:id],
        name: raw[:name]
      )
    end
  end
end

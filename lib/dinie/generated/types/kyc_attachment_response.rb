# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class KycAttachmentResponse < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end
end

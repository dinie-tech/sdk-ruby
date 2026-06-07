# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

module Dinie
  module Events
    class LoanSigner < Internal::Model
      attribute :cpf, :name, :signed_at

      def self.deserialize(raw)
        new(
          cpf: raw[:cpf],
          name: raw[:name],
          signed_at: raw[:signed_at]
        )
      end
    end

    class LoanSignatureReceivedData < Internal::Model
      attribute :id, :signatures_received, :signatures_required, :signer, :status

      def self.deserialize(raw)
        new(
          id: raw[:id],
          signatures_received: raw[:signatures_received],
          signatures_required: raw[:signatures_required],
          signer: LoanSigner.deserialize(raw[:signer]),
          status: raw[:status]
        )
      end
    end

    class LoanSignatureReceived < WebhookEventBase
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanSignatureReceivedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.signature_received"
        )
      end
    end
  end
end

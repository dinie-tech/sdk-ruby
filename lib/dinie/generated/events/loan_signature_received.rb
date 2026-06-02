# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.signature_received` event (`WebhookEvent_LoanSignatureReceived`) — architecture §3.1, §8.
# Fires each time an individual signer completes their signature on the CCB. Hand-authored in V0.3;
# ports `sdk-js` `src/generated/events/loan-signature-received.ts` (@ `19c9bca`). DS-EVENT.
#
# `data` carries a NESTED `signer` object — hydrated by its own {LoanSigner.deserialize} (DS-EVENT
# recurses into nested objects via a per-object hydrator, never a generic transform). NOT the
# `Loan` read-model.
module Dinie
  module Events
    # The signer whose signature was just captured (nested in {LoanSignatureReceivedData}).
    class LoanSigner < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :cpf, :name, :signed_at

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanSigner]
      def self.deserialize(raw)
        new(
          cpf: raw[:cpf],
          name: raw[:name],
          signed_at: raw[:signed_at]
        )
      end
    end

    # Payload of a `loan.signature_received` event. `status` pinned to `awaiting_signatures`.
    class LoanSignatureReceivedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :id, :signatures_received, :signatures_required, :signer, :status

      # Hydrate the payload; the nested `signer` runs through {LoanSigner.deserialize}.
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanSignatureReceivedData]
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

    # A verified `loan.signature_received` event (envelope + {LoanSignatureReceivedData}).
    class LoanSignatureReceived < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanSignatureReceived]
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

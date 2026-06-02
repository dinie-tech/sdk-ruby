# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "../types/kyc"
require_relative "base"

# `customer.kyc_updated` event (`WebhookEvent_CustomerKycUpdated`) — architecture §3.1, §8. Carries
# the full current state of all KYC requirements after a delta. Hand-authored in V0.3; ports
# `sdk-js` `src/generated/events/customer-kyc-updated.ts` (@ `19c9bca`). Follows DS-EVENT.
#
# `data` ({CustomerKycUpdatedData}) is the bespoke KYC-update payload (`{id, external_id, status,
# kyc}`). Like `customer.created`, its `kyc` array reuses {Dinie::Kyc.deserialize_requirement} —
# the only shared sub-object hydrator (the discriminated union from story 009). NOT the `Customer`
# read-model. This pairing is the version's highest fix-cycle risk (embedded discriminated union).
module Dinie
  module Events
    # Payload of a `customer.kyc_updated` event — the full current KYC state plus status.
    class CustomerKycUpdatedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :external_id, :id, :kyc, :status

      # Hydrate the payload; `kyc` runs each entry through {Dinie::Kyc.deserialize_requirement}
      # (the pinned public discriminated dispatch).
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [CustomerKycUpdatedData]
      def self.deserialize(raw)
        new(
          external_id: raw[:external_id],
          id: raw[:id],
          kyc: raw[:kyc].map { |requirement| Dinie::Kyc.deserialize_requirement(requirement) },
          status: raw[:status]
        )
      end
    end

    # A verified `customer.kyc_updated` event (envelope + {CustomerKycUpdatedData}).
    class CustomerKycUpdated < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CustomerKycUpdated]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerKycUpdatedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.kyc_updated"
        )
      end
    end
  end
end

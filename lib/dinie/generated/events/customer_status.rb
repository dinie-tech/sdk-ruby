# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `customer.under_review` + `customer.active` events (`WebhookEvent_CustomerStatus`) —
# architecture §3.1, §8. ONE openapi schema, TWO event classes (the `type` `enum` carries both).
# Hand-authored in V0.3; ports `sdk-js` `src/generated/events/customer-status.ts` (@ `19c9bca`).
#
# ── DS-EVENT, multi-type schema ──
# A schema whose `type` is an `enum` of N values yields N event classes that SHARE one `*Data`
# model + one hydrator, but each pins its OWN `type` literal in its `deserialize` (so the returned
# member is the exact class — no mislabel: {DESERIALIZERS} routes the right key to the right class).
# The partner still discriminates by class (`when Dinie::Events::CustomerActive`).
#
# `data` ({CustomerStatusData}) is the minimal status payload (`{id, external_id, status}`) — NOT
# the `Customer` read-model. See `customer_created.rb` for why the resource hydrators are not reused.
module Dinie
  module Events
    # Payload shared by `customer.under_review` and `customer.active` — the minimal status change
    # the Core emits. `status` carries the schema enum (not narrowed per member).
    class CustomerStatusData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :external_id, :id, :status

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [CustomerStatusData]
      def self.deserialize(raw)
        new(
          external_id: raw[:external_id],
          id: raw[:id],
          status: raw[:status]
        )
      end
    end

    # A verified `customer.under_review` event (envelope + {CustomerStatusData}).
    class CustomerUnderReview < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CustomerUnderReview]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.under_review"
        )
      end
    end

    # A verified `customer.active` event (envelope + {CustomerStatusData}).
    class CustomerActive < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CustomerActive]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.active"
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `credit_offer.available` + `credit_offer.expired` events (`WebhookEvent_CreditOffer`) —
# architecture §3.1, §8. ONE openapi schema, TWO event classes (the `type` `enum`). Hand-authored
# in V0.3; ports `sdk-js` `src/generated/events/credit-offer.ts` (@ `19c9bca`). Follows DS-EVENT.
#
# `data` ({CreditOfferEventData}) is the bespoke offer payload — NOT the `Dinie::CreditOffer`
# read-model (`types/credit_offer.rb`): it has NO `created_at`/`updated_at`, no `min_installments`/
# `max_installments`, `installments` is required, and `external_id` is required-but-nullable here.
# So `CreditOffer.deserialize` is NOT reused. The name carries the `Event` infix to mark it as the
# event-specific shape (mirrors the golden `CreditOfferEventData`). `approved_amount` is a `Money`
# (a plain `Float`, BRL — see `types/money.rb`); `min_amount`/`monthly_interest_rate` are `Float`.
# `due_date_rule` is `nil` when absent (R-OPTIONAL on hydrate).
module Dinie
  module Events
    # Payload shared by `credit_offer.available` and `credit_offer.expired`. `status` carries the
    # schema enum (not narrowed per member).
    class CreditOfferEventData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :approved_amount, :customer_id, :due_date_rule, :external_id, :id, :installments,
                :min_amount, :monthly_interest_rate, :status, :valid_until

      # Hydrate the shared credit-offer payload. `approved_amount` stays `Float` (Money);
      # `valid_until` stays `Integer` (epoch, R-EPOCH); `due_date_rule` is `nil` when absent.
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [CreditOfferEventData]
      def self.deserialize(raw)
        new(
          approved_amount: raw[:approved_amount],
          customer_id: raw[:customer_id],
          due_date_rule: raw[:due_date_rule],
          external_id: raw[:external_id],
          id: raw[:id],
          installments: raw[:installments],
          min_amount: raw[:min_amount],
          monthly_interest_rate: raw[:monthly_interest_rate],
          status: raw[:status],
          valid_until: raw[:valid_until]
        )
      end
    end

    # A verified `credit_offer.available` event (envelope + {CreditOfferEventData}).
    class CreditOfferAvailable < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CreditOfferAvailable]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CreditOfferEventData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "credit_offer.available"
        )
      end
    end

    # A verified `credit_offer.expired` event (envelope + {CreditOfferEventData}).
    class CreditOfferExpired < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CreditOfferExpired]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CreditOfferEventData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "credit_offer.expired"
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "../types/kyc"
require_relative "base"

# `customer.created` event (`WebhookEvent_CustomerCreated`) — architecture §3.1, §8. Fires after
# co-owner enrichment populates the KYC requirements; the customer is at `pending_kyc`. Hand-
# authored in V0.3; ports `sdk-js` `src/generated/events/customer-created.ts` (@ `19c9bca`).
#
# ════════════════════════════════════════════════════════════════════════════════
# DS-EVENT (per-type webhook deserialization, architecture §8 / frozen surface §"events").
# For each event schema the V0.5 generator emits, in order:
#   1. a `*Data` model — the typed `data` payload (R-ORDER alphabetical);
#   2. one event class per `type` — `< WebhookEventBase`, inheriting the seven envelope fields;
#   3. each event's `self.deserialize(raw)` — envelope INLINED (R-ORDER), `data` DELEGATED to the
#      `*Data` model's `deserialize`. The 15 `deserialize` are aggregated into {DESERIALIZERS}
#      (`deserializers.rb`), and `runtime/webhooks.rb` dispatches `DESERIALIZERS[raw[:type]].call`.
# ════════════════════════════════════════════════════════════════════════════════
#
# ── ⚠️ The `data` is a BESPOKE event payload, NOT the `Customer` read-model ──
# `WebhookEvent_CustomerCreated.data` (@3fcfd83) is a SLIMMER, event-specific shape — NOT the
# `Dinie::Customer` from `types/customer.rb`: it has NO `created_at`/`updated_at`, `name`/
# `trading_name` are required (non-null), `kyc` is REQUIRED, and `status` is pinned to
# `pending_kyc`. So this event does NOT reuse `Customer.deserialize` (its hydrate reads fields the
# event does not carry). The ONLY shared sub-object hydrator is {Dinie::Kyc.deserialize_requirement}
# (the discriminated union from story 009), reused for `data.kyc` here and in `customer.kyc_updated`.
# This is the "recurse into sub-objects via the data types' deserializers" of §8, made precise:
# per-type, never a generic deep symbolize (which would corrupt free-form maps).
#
# ── R-OPTIONAL on hydrate (the Ruby manifestation) ──
# `cnpj` is optional on the wire. Following the established hydrate convention (`credit_offer.rb`),
# the attribute is ALWAYS declared and `deserialize` passes `raw[:cnpj]` — `nil` when absent (Ruby
# collapses absent/null on reads). No key is dropped; `data.cnpj` simply reads `nil`.
module Dinie
  module Events
    # Payload of a `customer.created` event — a bespoke subset of the customer (no timestamps;
    # `kyc` required). NOT the `Customer` read-model.
    class CustomerCreatedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :cnpj, :cpf, :email, :external_id, :id, :kyc, :name, :phone, :status, :trading_name

      # Hydrate the bespoke `customer.created` payload. `kyc` runs each entry through
      # {Dinie::Kyc.deserialize_requirement} (the discriminated dispatch); `cnpj` is `nil` when
      # the wire omits it (R-OPTIONAL on hydrate).
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [CustomerCreatedData]
      def self.deserialize(raw)
        new(
          cnpj: raw[:cnpj],
          cpf: raw[:cpf],
          email: raw[:email],
          external_id: raw[:external_id],
          id: raw[:id],
          kyc: raw[:kyc].map { |requirement| Dinie::Kyc.deserialize_requirement(requirement) },
          name: raw[:name],
          phone: raw[:phone],
          status: raw[:status],
          trading_name: raw[:trading_name]
        )
      end
    end

    # A verified `customer.created` event (envelope + {CustomerCreatedData}).
    class CustomerCreated < WebhookEventBase
      # Hydrate a full `customer.created` event: envelope inlined (R-ORDER), `data` delegated.
      #
      # @param raw [Hash{Symbol => Object}] the wire event (snake_case keys)
      # @return [CustomerCreated]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerCreatedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.created"
        )
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `customer.denied` event (`WebhookEvent_CustomerDenied`) — architecture §3.1, §8. Fires when the
# customer is permanently blocked (fraud, closed company, other terminal condition). Hand-authored
# in V0.3; ports `sdk-js` `src/generated/events/customer-denied.ts` (@ `19c9bca`). Follows DS-EVENT
# (see `customer_created.rb`).
#
# `data` ({CustomerDeniedData}) is the bespoke denied payload (`{id, external_id, name, email,
# phone, cpf, cnpj?, status: 'denied'}`) — NOT the `Customer` read-model (no timestamps/kyc/
# trading_name). `cnpj` is `nil` when absent (R-OPTIONAL on hydrate).
module Dinie
  module Events
    # Payload of a `customer.denied` event. `status` is pinned to `denied`.
    class CustomerDeniedData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :cnpj, :cpf, :email, :external_id, :id, :name, :phone, :status

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [CustomerDeniedData]
      def self.deserialize(raw)
        new(
          cnpj: raw[:cnpj],
          cpf: raw[:cpf],
          email: raw[:email],
          external_id: raw[:external_id],
          id: raw[:id],
          name: raw[:name],
          phone: raw[:phone],
          status: raw[:status]
        )
      end
    end

    # A verified `customer.denied` event (envelope + {CustomerDeniedData}).
    class CustomerDenied < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [CustomerDenied]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: CustomerDeniedData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "customer.denied"
        )
      end
    end
  end
end

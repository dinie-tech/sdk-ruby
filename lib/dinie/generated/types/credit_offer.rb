# frozen_string_literal: true

require_relative "../../runtime/model"

# `CreditOffer` — a pre-approved credit offer (`co_…`), read-only (architecture §3.3, §6).
# Hand-authored in V0.3 to mirror future generator output; `components.schemas.CreditOffer`
# (`openapi.yaml @ 3fcfd83`) is the SoT. Follows the hydrate/dump convention documented in
# `customer.rb` (THE exemplar).
#
# ── Read-only (R10): deserialize only, no serializer ──
# Credit offers are minted by the Core (the `credit_offer.available` webhook), never POSTed by
# the partner — there is NO `POST /credit-offers` — so this type has a `deserialize` (hydrate)
# and NO `serialize_*` (dump). Hoisted to the foundational layer because it is cross-referenced
# by `customers.credit_offers.list` (007), the `credit_offers` resource (008) and the
# `credit_offer.*` webhook events (011).
#
# ── installments XOR (architecture §3.5) ──
# The product is EITHER fixed-count (`installments`) XOR a range (`min_installments` +
# `max_installments`). A generator cannot infer mutual exclusivity from prose, so all three
# are declared attributes and the exclusivity is documented, not enforced. (Contract note:
# openapi lists `installments` in `required` yet its own description says a range offer omits
# it — the architecture §3.5 "three optional" decision wins; tracked for conformance, 012.)
#
# ── Field map (`components.schemas.CreditOffer` @ 3fcfd83) — wire snake = surface snake ──
#   approved_amount        → Money (Float, BRL)
#   created_at             → Integer       (epoch seconds, R-EPOCH)
#   customer_id            → CustomerId    (`cust_…`)
#   due_date_rule          → String | nil  (optional, nullable; pending Core)
#   external_id            → String | nil  (optional)
#   id                     → CreditOfferId (`co_…`)
#   installments           → Integer | nil (XOR — see note)
#   max_installments       → Integer | nil (XOR)
#   min_amount             → Float (BRL)
#   min_installments       → Integer | nil (XOR)
#   monthly_interest_rate  → Float (percent)
#   status                 → String        (CreditOfferStatus enum)
#   updated_at             → Integer       (epoch seconds, R-EPOCH)
#   valid_until            → Integer       (epoch seconds)
module Dinie
  # A pre-approved credit offer for a customer (`co_…`) — read-only (R10).
  class CreditOffer < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :approved_amount, :created_at, :customer_id, :due_date_rule, :external_id,
              :id, :installments, :max_installments, :min_amount, :min_installments,
              :monthly_interest_rate, :status, :updated_at, :valid_until

    # Hydrate a wire credit offer (symbol-keyed Hash) into a {CreditOffer}. Explicit per-field
    # (R-EXPLICIT) — never a blind symbolize/slice — so a contract drift surfaces as an
    # ArgumentError from the base initializer (the completeness forcing-function), not as
    # silently dropped data. Absent optionals arrive as `nil`; epoch fields stay `Integer`
    # (R-EPOCH); `Money` (`approved_amount`) stays `Float`.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [CreditOffer]
    def self.deserialize(raw)
      new(
        approved_amount: raw[:approved_amount],
        created_at: raw[:created_at],
        customer_id: raw[:customer_id],
        due_date_rule: raw[:due_date_rule],
        external_id: raw[:external_id],
        id: raw[:id],
        installments: raw[:installments],
        max_installments: raw[:max_installments],
        min_amount: raw[:min_amount],
        min_installments: raw[:min_installments],
        monthly_interest_rate: raw[:monthly_interest_rate],
        status: raw[:status],
        updated_at: raw[:updated_at],
        valid_until: raw[:valid_until]
      )
    end
  end
end

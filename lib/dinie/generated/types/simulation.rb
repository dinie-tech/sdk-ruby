# frozen_string_literal: true

require_relative "../../runtime/model"

# `Simulation` + its `CreateSimulationRequest` dump — the result of pricing a credit offer
# (`sim_…`). Hand-authored in V0.3 to mirror future generator output; the SoT is
# `components.schemas.Simulation` / `CreateSimulationRequest` (`openapi.yaml @ 3fcfd83`).
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar).
#
# ── Read model AND request body ──
# `credit_offers.create_simulation(credit_offer_id, requested_amount:, installment_count:)`
# POSTs a `CreateSimulationRequest` (the dump) and the API answers with a `Simulation` (the
# hydrate), so this type carries BOTH `self.deserialize` and `self.serialize_create`.
#
# ── Field map (`components.schemas.Simulation` @ 3fcfd83) — wire snake = surface snake ──
# Every field is `required` in the contract (no optional/nullable members). All money/rate
# fields are plain `Float` (`Money` is `type: number` — see `money.rb`); `first_due_date` is an
# ISO-8601 date `String` (kept verbatim, not coerced to `Date` — fidelity to the wire, same
# rationale as R-EPOCH); `created_at` is epoch `Integer` (R-EPOCH); `installment_count` is
# `Integer`.
#
#   annual_cet_rate        → Float          (percent)
#   annual_interest_rate   → Float          (percent)
#   created_at             → Integer        (epoch seconds, R-EPOCH)
#   credit_offer_id        → CreditOfferId  (`co_…`)
#   fee_amount             → Float          (Money — TC)
#   first_due_date         → String         (ISO-8601 date)
#   id                     → SimulationId   (`sim_…`)
#   installment_amount     → Float          (Money)
#   installment_count      → Integer
#   interest_amount        → Float          (Money)
#   iof_amount             → Float          (Money — IOF tax)
#   monthly_cet_rate       → Float          (percent)
#   monthly_interest_rate  → Float          (percent)
#   principal_amount       → Float          (Money)
#   requested_amount       → Float          (Money)
#   total_amount           → Float          (Money — sum of installments)
module Dinie
  # A loan simulation for a credit offer (`sim_…`) — calculated pricing the partner can chain
  # back into `loans.create`.
  class Simulation < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :annual_cet_rate, :annual_interest_rate, :created_at, :credit_offer_id,
              :fee_amount, :first_due_date, :id, :installment_amount, :installment_count,
              :interest_amount, :iof_amount, :monthly_cet_rate, :monthly_interest_rate,
              :principal_amount, :requested_amount, :total_amount

    # Hydrate a wire simulation (symbol-keyed Hash) into a {Simulation}. Explicit per-field
    # (R-EXPLICIT); epoch (`created_at`) stays `Integer` (R-EPOCH); money/rate fields stay
    # `Float`; `first_due_date` stays an ISO date `String`.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [Simulation]
    def self.deserialize(raw)
      new(
        annual_cet_rate: raw[:annual_cet_rate],
        annual_interest_rate: raw[:annual_interest_rate],
        created_at: raw[:created_at],
        credit_offer_id: raw[:credit_offer_id],
        fee_amount: raw[:fee_amount],
        first_due_date: raw[:first_due_date],
        id: raw[:id],
        installment_amount: raw[:installment_amount],
        installment_count: raw[:installment_count],
        interest_amount: raw[:interest_amount],
        iof_amount: raw[:iof_amount],
        monthly_cet_rate: raw[:monthly_cet_rate],
        monthly_interest_rate: raw[:monthly_interest_rate],
        principal_amount: raw[:principal_amount],
        requested_amount: raw[:requested_amount],
        total_amount: raw[:total_amount]
      )
    end

    # Dump a `CreateSimulationRequest` wire body from idiomatic kwargs (RB4). Both fields are
    # required by the contract — there is no optional member, so no `Internal::OMIT` handling is
    # needed. Keys alphabetical (R-ORDER).
    #
    # @param installment_count [Integer] required, number of installments (>= 1)
    # @param requested_amount [Float] required, requested loan amount
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_create(installment_count:, requested_amount:)
      { installment_count:, requested_amount: }
    end
  end
end

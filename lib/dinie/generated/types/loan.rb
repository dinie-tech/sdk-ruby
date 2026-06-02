# frozen_string_literal: true

require_relative "../../runtime/model"

# `Loan` + its `CreateLoanRequest` dump — a contracted loan (`ln_…`). Hand-authored in V0.3 to
# mirror future generator output; the SoT is `components.schemas.Loan` / `CreateLoanRequest`
# (`openapi.yaml @ 3fcfd83`). Follows the hydrate/dump convention documented in `customer.rb`
# (THE exemplar).
#
# ── Read model AND request body ──
# `loans.create(credit_offer_id:, simulation_id:, installment_count:, installment_amount:,
# first_due_date:)` POSTs a `CreateLoanRequest` (the dump — 5 required fields, the partner
# chains the accepted simulation back) and the API answers with a `Loan` (the hydrate), so this
# type carries BOTH `self.deserialize` and `self.serialize_create`.
#
# ── Field map (`components.schemas.Loan` @ 3fcfd83) — wire snake = surface snake ──
# Every field is `required`; several are required-NULLABLE — they always travel on the wire but
# may be `null` until the Core computes/produces them. On hydrate a `null` simply arrives as
# `nil` (Ruby collapses absent/null on reads). `requested_amount`/`total_amount` are `Money`
# (`Float`); the rate fields are `Float`; `created_at`/`updated_at` are epoch `Integer`
# (R-EPOCH); `first_due_date` is an ISO date `String`.
#
#   annual_cet_rate        → Float            (percent)
#   annual_interest_rate   → Float            (percent)
#   ccb_number             → String | nil     (null until the CCB contract is generated)
#   created_at             → Integer          (epoch seconds, R-EPOCH)
#   credit_offer_id        → CreditOfferId    (`co_…`)
#   customer_id            → CustomerId       (`cust_…`)
#   disbursement_method    → String | nil     (e.g. `pix`; null until disbursement)
#   first_due_date         → String           (ISO-8601 date)
#   id                     → LoanId           (`ln_…`)
#   installment_amount     → Float            (Money)
#   installment_count      → Integer
#   iof_amount             → Float | nil      (IOF tax; null until calculated)
#   monthly_cet_rate       → Float            (percent)
#   monthly_interest_rate  → Float            (percent)
#   principal_amount       → Float | nil      (principal + financed fees; null until calculated)
#   requested_amount       → Float            (Money)
#   signing_url            → String | nil     (ClickSign URL; present only while awaiting_signatures)
#   simulation_id          → SimulationId     (`sim_…`)
#   status                 → String           (LoanStatus enum)
#   total_amount           → Float            (Money — sum of installments)
#   updated_at             → Integer          (epoch seconds, R-EPOCH)
module Dinie
  # A contracted loan (`ln_…`) created from an accepted credit-offer simulation.
  class Loan < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :annual_cet_rate, :annual_interest_rate, :ccb_number, :created_at,
              :credit_offer_id, :customer_id, :disbursement_method, :first_due_date, :id,
              :installment_amount, :installment_count, :iof_amount, :monthly_cet_rate,
              :monthly_interest_rate, :principal_amount, :requested_amount, :signing_url,
              :simulation_id, :status, :total_amount, :updated_at

    # Hydrate a wire loan (symbol-keyed Hash) into a {Loan}. Explicit per-field (R-EXPLICIT);
    # epoch fields stay `Integer` (R-EPOCH); money/rate fields stay `Float`; the
    # required-nullable fields (`ccb_number`/`disbursement_method`/`iof_amount`/`principal_amount`/
    # `signing_url`) arrive as `nil` while the Core has not produced them yet.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [Loan]
    def self.deserialize(raw)
      new(
        annual_cet_rate: raw[:annual_cet_rate],
        annual_interest_rate: raw[:annual_interest_rate],
        ccb_number: raw[:ccb_number],
        created_at: raw[:created_at],
        credit_offer_id: raw[:credit_offer_id],
        customer_id: raw[:customer_id],
        disbursement_method: raw[:disbursement_method],
        first_due_date: raw[:first_due_date],
        id: raw[:id],
        installment_amount: raw[:installment_amount],
        installment_count: raw[:installment_count],
        iof_amount: raw[:iof_amount],
        monthly_cet_rate: raw[:monthly_cet_rate],
        monthly_interest_rate: raw[:monthly_interest_rate],
        principal_amount: raw[:principal_amount],
        requested_amount: raw[:requested_amount],
        signing_url: raw[:signing_url],
        simulation_id: raw[:simulation_id],
        status: raw[:status],
        total_amount: raw[:total_amount],
        updated_at: raw[:updated_at]
      )
    end

    # Dump a `CreateLoanRequest` wire body from idiomatic kwargs (RB4). All five fields are
    # required by the contract — there is no optional member, so no `Internal::OMIT` handling is
    # needed. Keys alphabetical (R-ORDER).
    #
    # @param credit_offer_id [String] required, the offer being contracted (`co_…`)
    # @param first_due_date [String] required, first installment due date (ISO-8601 date)
    # @param installment_amount [Float] required, the accepted installment amount
    # @param installment_count [Integer] required, the accepted number of installments (>= 1)
    # @param simulation_id [String] required, the accepted simulation (`sim_…`)
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_create(credit_offer_id:, first_due_date:, installment_amount:,
                              installment_count:, simulation_id:)
      { credit_offer_id:, first_due_date:, installment_amount:, installment_count:, simulation_id: }
    end
  end
end

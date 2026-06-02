# frozen_string_literal: true

require_relative "../../runtime/model"

# `Transaction` — one installment of a loan (`tx_…`), read-only. Hand-authored in V0.3 to mirror
# future generator output; the SoT is `components.schemas.Transaction` (`openapi.yaml @ 3fcfd83`).
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar).
#
# ── Read-only: deserialize only, no serializer ──
# Transactions are produced by the Core as a loan amortizes (listed via
# `loans.transactions.list`); the partner never POSTs one — there is no `CreateTransactionRequest`
# — so this type has a `deserialize` (hydrate) and NO `serialize_*` (dump), like `CreditOffer`.
#
# ── Field map (`components.schemas.Transaction` @ 3fcfd83) — wire snake = surface snake ──
# Every field is `required`; `paid_at` is required-NULLABLE (`nil` until payment). All six money
# fields are plain `Float` (`Money` is `type: number` — see `money.rb`); `due_date` is an
# ISO-8601 date `String`; `created_at`/`updated_at` are epoch `Integer` (R-EPOCH); `type` is the
# constant String `"installment"`.
#
#   amount_due        → Float          (Money)
#   amount_paid       → Float          (Money)
#   amount_remaining  → Float          (Money)
#   created_at        → Integer        (epoch seconds, R-EPOCH)
#   days_overdue      → Integer        (0 when not overdue)
#   due_date          → String         (ISO-8601 date)
#   fees              → Float          (Money)
#   id                → TransactionId  (`tx_…`)
#   interest          → Float          (Money)
#   loan_id           → LoanId         (`ln_…`)
#   paid_at           → Integer | nil  (epoch seconds; null until paid, R-EPOCH)
#   principal         → Float          (Money)
#   status            → String         (TransactionStatus enum)
#   type              → String         (const `"installment"` — TransactionType)
#   updated_at        → Integer        (epoch seconds, R-EPOCH)
module Dinie
  # One installment of a loan (`tx_…`) — read-only, produced by the Core as the loan amortizes.
  class Transaction < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :amount_due, :amount_paid, :amount_remaining, :created_at, :days_overdue,
              :due_date, :fees, :id, :interest, :loan_id, :paid_at, :principal, :status,
              :type, :updated_at

    # Hydrate a wire transaction (symbol-keyed Hash) into a {Transaction}. Explicit per-field
    # (R-EXPLICIT); epoch fields (`created_at`/`updated_at`/`paid_at`) stay `Integer` (R-EPOCH);
    # money fields stay `Float`; `paid_at` arrives as `nil` until the installment is paid.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [Transaction]
    def self.deserialize(raw)
      new(
        amount_due: raw[:amount_due],
        amount_paid: raw[:amount_paid],
        amount_remaining: raw[:amount_remaining],
        created_at: raw[:created_at],
        days_overdue: raw[:days_overdue],
        due_date: raw[:due_date],
        fees: raw[:fees],
        id: raw[:id],
        interest: raw[:interest],
        loan_id: raw[:loan_id],
        paid_at: raw[:paid_at],
        principal: raw[:principal],
        status: raw[:status],
        type: raw[:type],
        updated_at: raw[:updated_at]
      )
    end
  end
end

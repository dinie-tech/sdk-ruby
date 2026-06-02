# frozen_string_literal: true

require_relative "../../runtime/model"

# `CustomerBankAccount` + the `CustomerBankAccountKind` enum (architecture §3.3, §6). Follows the
# hydrate/dump convention documented in `customer.rb` (THE exemplar). Hand-authored in V0.3 to
# mirror future generator output; `components.schemas.CustomerBankAccount` /
# `CustomerBankAccountRequest` (`openapi.yaml @ 3fcfd83`) are the SoT.
#
# ── allOf flattened into one read model (architecture §6.2) ──
# The contract models `CustomerBankAccount` as `allOf [CustomerBankAccountRequest, {id, bank_name,
# updated_at}]`. The request half (`CustomerBankAccountRequest`) is a write-only shape with no
# read-model of its own, so rather than emit a near-empty base class this type declares the union
# of all fields directly and carries the request shape as its `serialize_upsert` dump. This is the
# read model returned by `customers.retrieve_bank_account` / `customers.upsert_bank_account`.
#
# ── Field map (`components.schemas.CustomerBankAccount` @ 3fcfd83) — wire snake = surface snake ──
#   bank_id     → String         (COMPE bank code; zero-padded to 3 digits when stored)
#   bank_name   → String         (resolved display name; read-only, added by the allOf delta)
#   branch      → String         (branch number without check digit; zero-padded to 4)
#   digit       → String         (account check digit — a single digit or "X")
#   id          → BankAccountId  (`ba_…`; read-only, added by the allOf delta)
#   kind        → String         (CustomerBankAccountKind enum)
#   number      → String         (account number)
#   updated_at  → Integer        (epoch seconds, R-EPOCH; read-only, added by the allOf delta)
module Dinie
  # Bank account kinds — `components.schemas.CustomerBankAccountRequest.kind` (openapi @ 3fcfd83).
  # A frozen module of named constants for discoverability (the value surfaces as a plain
  # `String`; the constants document and name the wire values, they do not validate).
  module CustomerBankAccountKind
    # Conta corrente.
    CHECKING = "checking"
    # Conta poupança.
    SAVING = "saving"
    # Conta de pagamento.
    PAYMENT = "payment"
    # Every valid value, in contract order.
    ALL = [CHECKING, SAVING, PAYMENT].freeze
  end

  # A customer's disbursement bank account (`ba_…`) — the read model returned by the bank-account
  # singleton endpoints.
  class CustomerBankAccount < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :bank_id, :bank_name, :branch, :digit, :id, :kind, :number, :updated_at

    # Hydrate a wire bank account (symbol-keyed Hash) into a {CustomerBankAccount}. Explicit
    # per-field (R-EXPLICIT); `updated_at` stays `Integer` (R-EPOCH).
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [CustomerBankAccount]
    def self.deserialize(raw)
      new(
        bank_id: raw[:bank_id],
        bank_name: raw[:bank_name],
        branch: raw[:branch],
        digit: raw[:digit],
        id: raw[:id],
        kind: raw[:kind],
        number: raw[:number],
        updated_at: raw[:updated_at]
      )
    end

    # Dump a bank-account upsert (`POST /customers/{id}/bank-account`) wire body from idiomatic
    # kwargs (RB4). The contract wraps the `CustomerBankAccountRequest` under a top-level
    # `bank_account` key; every field is required, so there is nothing to drop. Keys alphabetical
    # (R-ORDER).
    #
    # @param bank_id [String] COMPE bank code (required)
    # @param branch [String] branch number without the check digit (required)
    # @param digit [String] account check digit — a single digit or "X" (required)
    # @param kind [String] one of {CustomerBankAccountKind} (required)
    # @param number [String] account number (required)
    # @return [Hash{Symbol => Object}] the wire request body, `{ bank_account: {...} }`
    def self.serialize_upsert(bank_id:, branch:, digit:, kind:, number:)
      { bank_account: { bank_id:, branch:, digit:, kind:, number: } }
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module CustomerBankAccountKind
    CHECKING = "checking"
    SAVING = "saving"
    PAYMENT = "payment"
    ALL = [CHECKING, SAVING, PAYMENT].freeze
  end

  class CustomerBankAccount < Internal::Model
    attribute :bank_id, :bank_name, :branch, :digit, :id, :kind, :number, :updated_at

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

    def self.serialize_upsert_bank_account(bank_id:, branch:, digit:, kind:, number:)
      { bank_account: { bank_id:, branch:, digit:, kind:, number: } }
    end
  end
end

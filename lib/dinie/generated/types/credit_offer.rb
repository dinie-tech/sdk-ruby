# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class FixedInstallmentCreditOffer < Internal::Model
    attribute :approved_amount, :created_at, :customer_id, :due_date_rule, :external_id, :id, :installments,
              :min_amount, :monthly_interest_rate, :status, :updated_at, :valid_until

    def self.deserialize(raw)
      new(
        approved_amount: raw[:approved_amount],
        created_at: raw[:created_at],
        customer_id: raw[:customer_id],
        due_date_rule: raw[:due_date_rule],
        external_id: raw[:external_id],
        id: raw[:id],
        installments: raw[:installments],
        min_amount: raw[:min_amount],
        monthly_interest_rate: raw[:monthly_interest_rate],
        status: raw[:status],
        updated_at: raw[:updated_at],
        valid_until: raw[:valid_until]
      )
    end
  end

  class RangeInstallmentCreditOffer < Internal::Model
    attribute :approved_amount, :created_at, :customer_id, :due_date_rule, :external_id, :id, :max_installments,
              :min_amount, :min_installments, :monthly_interest_rate, :status, :updated_at, :valid_until

    def self.deserialize(raw)
      new(
        approved_amount: raw[:approved_amount],
        created_at: raw[:created_at],
        customer_id: raw[:customer_id],
        due_date_rule: raw[:due_date_rule],
        external_id: raw[:external_id],
        id: raw[:id],
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

  module CreditOffer
    def self.deserialize(raw)
      if raw.key?(:installments)
        FixedInstallmentCreditOffer.deserialize(raw)
      elsif raw.key?(:max_installments)
        RangeInstallmentCreditOffer.deserialize(raw)
      else
        RangeInstallmentCreditOffer.deserialize(raw)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module TransactionStatus
    PENDING = "pending"
    PAID = "paid"
    OVERDUE = "overdue"
    PARTIALLY_PAID = "partially_paid"
    ALL = [PENDING, PAID, OVERDUE, PARTIALLY_PAID].freeze
  end

  module TransactionType
    INSTALLMENT = "installment"
    ALL = [INSTALLMENT].freeze
  end

  class Transaction < Internal::Model
    attribute :amount_due, :amount_paid, :amount_remaining, :created_at, :days_overdue, :due_date, :fees, :id,
              :interest, :loan_id, :paid_at, :principal, :status, :type, :updated_at

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

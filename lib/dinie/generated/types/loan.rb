# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module LoanStatus
    AWAITING_SIGNATURES = "awaiting_signatures"
    PROCESSING = "processing"
    ACTIVE = "active"
    FINISHED = "finished"
    CANCELLED = "cancelled"
    ERROR = "error"
    ALL = [AWAITING_SIGNATURES, PROCESSING, ACTIVE, FINISHED, CANCELLED, ERROR].freeze
  end

  class Loan < Internal::Model
    attribute :annual_cet_rate, :annual_interest_rate, :ccb_number, :created_at, :credit_offer_id, :customer_id,
              :disbursement_method, :first_due_date, :id, :installment_amount, :installment_count, :iof_amount, :monthly_cet_rate, :monthly_interest_rate, :principal_amount, :requested_amount, :signing_url, :simulation_id, :status, :total_amount, :updated_at

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

    def self.serialize_create(credit_offer_id:, first_due_date:, installment_amount:, installment_count:,
                              simulation_id:)
      { credit_offer_id:, first_due_date:, installment_amount:, installment_count:, simulation_id: }
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  class Simulation < Internal::Model
    attribute :annual_cet_rate, :annual_interest_rate, :created_at, :credit_offer_id, :fee_amount, :first_due_date,
              :id, :installment_amount, :installment_count, :interest_amount, :iof_amount, :monthly_cet_rate, :monthly_interest_rate, :principal_amount, :requested_amount, :total_amount

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

    def self.serialize_create_simulation(installment_count:, requested_amount:)
      { installment_count:, requested_amount: }
    end
  end
end

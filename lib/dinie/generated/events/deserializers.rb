# frozen_string_literal: true

require_relative "credit_offer"
require_relative "customer_created"
require_relative "customer_denied"
require_relative "customer_kyc_updated"
require_relative "customer_status"
require_relative "loan_active"
require_relative "loan_created"
require_relative "loan_payment_received"
require_relative "loan_processing"
require_relative "loan_signature_received"
require_relative "loan_status"

module Dinie
  module Events
    DESERIALIZERS = {
      "credit_offer.available" => ->(raw) { CreditOfferAvailable.deserialize(raw) },
      "credit_offer.expired" => ->(raw) { CreditOfferExpired.deserialize(raw) },
      "customer.active" => ->(raw) { CustomerActive.deserialize(raw) },
      "customer.under_review" => ->(raw) { CustomerUnderReview.deserialize(raw) },
      "customer.created" => ->(raw) { CustomerCreated.deserialize(raw) },
      "customer.denied" => ->(raw) { CustomerDenied.deserialize(raw) },
      "customer.kyc_updated" => ->(raw) { CustomerKycUpdated.deserialize(raw) },
      "loan.active" => ->(raw) { LoanActive.deserialize(raw) },
      "loan.cancelled" => ->(raw) { LoanCancelled.deserialize(raw) },
      "loan.error" => ->(raw) { LoanErrorEvent.deserialize(raw) },
      "loan.finished" => ->(raw) { LoanFinished.deserialize(raw) },
      "loan.created" => ->(raw) { LoanCreated.deserialize(raw) },
      "loan.payment_received" => ->(raw) { LoanPaymentReceived.deserialize(raw) },
      "loan.processing" => ->(raw) { LoanProcessing.deserialize(raw) },
      "loan.signature_received" => ->(raw) { LoanSignatureReceived.deserialize(raw) }
    }.freeze
  end
end

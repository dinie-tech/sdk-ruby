# frozen_string_literal: true

module Dinie
  module Internal
    ID_PATTERNS = {
      api_client: /\Adinie_ci_(live|test)_[A-Za-z0-9]+\z/,
      bank_account: /\Aba_[0-9a-f]{32}\z/,
      credit_offer: /\Aco_[0-9a-f]{32}\z/,
      customer: /\Acust_[0-9a-f]{32}\z/,
      event: /\Aevt_[0-9a-f]{32}\z/,
      loan: /\Aln_[0-9a-f]{32}\z/,
      simulation: /\Asim_[0-9a-f]{32}\z/,
      transaction: /\Atx_[0-9a-f]{32}\z/,
      webhook_delivery: /\Adlv_[0-9a-f]{32}\z/,
      webhook_endpoint: /\Awe_[0-9a-f]{32}\z/
    }.freeze
  end
end

# frozen_string_literal: true

# Enum value catalogs for the foundational types (architecture §3.3).
#
# The OpenAPI enums are string unions; the SDK surfaces the value as a plain `String` (the
# wire value, unchanged) and ADDS a frozen module of named constants per enum for
# discoverability — a Ruby-specific affordance (TS encodes enums as literal-union *types*
# only; Ruby has no literal-union type, so RBS carries the union — story 013 — and these
# constants carry the values). The constants do NOT impose validation; they document and name
# the values. `ALL` lists every value in contract order, for iteration and conformance use.
#
# Scope: the foundational enums (Customer, Credential, CreditOffer) PLUS the credit-flow enums
# (Loan/Transaction) added by story 008 PLUS the platform enums (WebhookEndpoint) added by
# story 010.
module Dinie
  # Customer lifecycle status — `components.schemas.Customer.status` (openapi @ 3fcfd83).
  module CustomerStatus
    # Cadastro em andamento, aguardando enriquecimento de dados.
    CREATING = "creating"
    # Aguardando envio dos documentos KYC.
    PENDING_KYC = "pending_kyc"
    # Documentos em análise.
    UNDER_REVIEW = "under_review"
    # Cliente aprovado e habilitado para ofertas de crédito.
    ACTIVE = "active"
    # Cliente negado permanentemente.
    DENIED = "denied"
    # Every valid value, in contract order.
    ALL = [CREATING, PENDING_KYC, UNDER_REVIEW, ACTIVE, DENIED].freeze
  end

  # Credential lifecycle status — `components.schemas.Credential.status`.
  module CredentialStatus
    ACTIVE = "active"
    REVOKED = "revoked"
    # Every valid value, in contract order.
    ALL = [ACTIVE, REVOKED].freeze
  end

  # Credit-offer lifecycle status — `components.schemas.CreditOffer.status`.
  module CreditOfferStatus
    # Oferta disponível para contratação.
    AVAILABLE = "available"
    # Oferta aceita e empréstimo criado.
    ACCEPTED = "accepted"
    # Oferta expirada e não mais disponível.
    EXPIRED = "expired"
    # Every valid value, in contract order.
    ALL = [AVAILABLE, ACCEPTED, EXPIRED].freeze
  end

  # Loan lifecycle status — `components.schemas.Loan.status` (story 008).
  module LoanStatus
    # Aguardando assinaturas da CCB.
    AWAITING_SIGNATURES = "awaiting_signatures"
    # Assinaturas coletadas, desembolso em andamento.
    PROCESSING = "processing"
    # Empréstimo ativo com parcelas em aberto.
    ACTIVE = "active"
    # Todas as parcelas pagas.
    FINISHED = "finished"
    # Empréstimo cancelado antes do desembolso.
    CANCELLED = "cancelled"
    # Erro durante o processamento do empréstimo.
    ERROR = "error"
    # Every valid value, in contract order.
    ALL = [AWAITING_SIGNATURES, PROCESSING, ACTIVE, FINISHED, CANCELLED, ERROR].freeze
  end

  # Transaction (installment) status — `components.schemas.Transaction.status` (story 008).
  module TransactionStatus
    # Parcela aguardando pagamento.
    PENDING = "pending"
    # Parcela paga integralmente.
    PAID = "paid"
    # Parcela vencida.
    OVERDUE = "overdue"
    # Parcela com pagamento parcial.
    PARTIALLY_PAID = "partially_paid"
    # Every valid value, in contract order.
    ALL = [PENDING, PAID, OVERDUE, PARTIALLY_PAID].freeze
  end

  # Transaction type — `components.schemas.Transaction.type` (story 008). A single-member `const`
  # in the contract today (`installment`); modelled as a one-value catalog for parity with the
  # other enums and forward-compatibility.
  module TransactionType
    # Parcela de um empréstimo.
    INSTALLMENT = "installment"
    # Every valid value, in contract order.
    ALL = [INSTALLMENT].freeze
  end

  # Webhook-endpoint status — `components.schemas.WebhookEndpoint.status` (story 010).
  module WebhookEndpointStatus
    # Endpoint ativo, recebendo eventos.
    ACTIVE = "active"
    # Endpoint desativado, sem entregas.
    DISABLED = "disabled"
    # Every valid value, in contract order.
    ALL = [ACTIVE, DISABLED].freeze
  end
end

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
# Scope: the three enums of the foundational types (Customer, Credential, CreditOffer).
# Resource-specific enums (loan/transaction/… status) land with their resources (007–010).
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
end

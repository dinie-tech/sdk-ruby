# frozen_string_literal: true

# Shared webhook fixtures for the events tier (`spec/generated/events_spec.rb`) and the `extract`
# tier (`spec/runtime/webhooks_spec.rb`). The 15 typed events keyed by `type`, each with its bespoke
# snake-native `data` wire, plus the Standard Webhooks envelope builder and an HMAC signer mirroring
# the verification mechanics under test. Wire shapes/values come from `openapi.yaml @ 3fcfd83`.
#
# The `webhook_event_table` is verbose fixture DATA (15 events × multi-line `data` wires), so the
# Metrics length cops are disabled for this support file — same intent as the generated layer's
# `.rubocop.yml` excludes, applied locally.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength
module WebhookEventFixtures
  # An embedded KYC requirement (the only reused sub-object hydrator — story 009 discriminated union).
  def kyc_requirement_wire
    {
      requirement_type: "selfie", requirement_id: "selfie_003XXXXXXXXXXXXXXX", label: "Selfie",
      mandatory: true,
      subject: { id: "003XXXXXXXXXXXXXXX", name: "Joao Silva", subject_type: "applicant" },
      submitted: {
        evidence_type: "selfie",
        attachments: [{ attachment_type: "photo", submitted_at: 1_772_791_200 }],
        review_status: "pending", review_reason: nil
      }
    }
  end

  # The shared Standard Webhooks envelope (R-ORDER alphabetical), wrapping a bespoke `data`.
  def webhook_envelope(type:, data:)
    {
      api_version: "2026-03-01", created_at: 1_772_791_200, data:, delivery_id: "dlv_abc123",
      id: "evt_550e8400e29b41d4a716446655440000", timestamp: 1_772_791_250, type:
    }
  end

  # The 15 events: `type` → event class + bespoke data class + a `status` value + the `data` wire.
  # Optional fields (`cnpj`, `due_date_rule`, `error`) are present as explicit values/`nil` so the
  # round-trip is exact (R-OPTIONAL on hydrate keeps the declared key).
  def webhook_event_table
    [
      { type: "customer.created", klass: Dinie::Events::CustomerCreated,
        data_klass: Dinie::Events::CustomerCreatedData, status: "pending_kyc",
        data: {
          cnpj: "12.345.678/0001-00", cpf: "123.456.789-00", email: "ana@example.com",
          external_id: "partner-ref-1", id: "cust_1", kyc: [kyc_requirement_wire], name: "Ana Lima",
          phone: "+5511999990000", status: "pending_kyc", trading_name: "Ana Lima ME"
        } },
      { type: "customer.under_review", klass: Dinie::Events::CustomerUnderReview,
        data_klass: Dinie::Events::CustomerStatusData, status: "under_review",
        data: { external_id: "partner-ref-1", id: "cust_1", status: "under_review" } },
      { type: "customer.active", klass: Dinie::Events::CustomerActive,
        data_klass: Dinie::Events::CustomerStatusData, status: "active",
        data: { external_id: nil, id: "cust_1", status: "active" } },
      { type: "customer.denied", klass: Dinie::Events::CustomerDenied,
        data_klass: Dinie::Events::CustomerDeniedData, status: "denied",
        data: {
          cnpj: nil, cpf: "123.456.789-00", email: "ana@example.com", external_id: "partner-ref-1",
          id: "cust_1", name: "Ana Lima", phone: "+5511999990000", status: "denied"
        } },
      { type: "customer.kyc_updated", klass: Dinie::Events::CustomerKycUpdated,
        data_klass: Dinie::Events::CustomerKycUpdatedData, status: "active",
        data: { external_id: "partner-ref-1", id: "cust_1", kyc: [kyc_requirement_wire], status: "active" } },
      { type: "credit_offer.available", klass: Dinie::Events::CreditOfferAvailable,
        data_klass: Dinie::Events::CreditOfferEventData, status: "available",
        data: {
          approved_amount: 5000.0, customer_id: "cust_1", due_date_rule: "monthly_on_5th",
          external_id: "partner-ref-1", id: "co_1", installments: 12, min_amount: 100.0,
          monthly_interest_rate: 2.5, status: "available", valid_until: 1_775_000_000
        } },
      { type: "credit_offer.expired", klass: Dinie::Events::CreditOfferExpired,
        data_klass: Dinie::Events::CreditOfferEventData, status: "expired",
        data: {
          approved_amount: 5000.0, customer_id: "cust_1", due_date_rule: nil,
          external_id: "partner-ref-1", id: "co_1", installments: 12, min_amount: 100.0,
          monthly_interest_rate: 2.5, status: "expired", valid_until: 1_775_000_000
        } },
      { type: "loan.created", klass: Dinie::Events::LoanCreated,
        data_klass: Dinie::Events::LoanCreatedData, status: "awaiting_signatures",
        data: {
          credit_offer_id: "co_1", customer_id: "cust_1", id: "ln_1", installment_count: 12,
          requested_amount: 5000.0, signing_url: "https://sign.clicksign.com/abc",
          status: "awaiting_signatures"
        } },
      { type: "loan.signature_received", klass: Dinie::Events::LoanSignatureReceived,
        data_klass: Dinie::Events::LoanSignatureReceivedData, status: "awaiting_signatures",
        data: {
          id: "ln_1", signatures_received: 1, signatures_required: 2,
          signer: { cpf: "123.456.789-00", name: "Ana Lima", signed_at: 1_772_791_200 },
          status: "awaiting_signatures"
        } },
      { type: "loan.processing", klass: Dinie::Events::LoanProcessing,
        data_klass: Dinie::Events::LoanProcessingData, status: "processing",
        data: {
          ccb_number: "CCB-2026-0001", credit_offer_id: "co_1", customer_id: "cust_1",
          disbursement_method: "pix", id: "ln_1", status: "processing"
        } },
      { type: "loan.active", klass: Dinie::Events::LoanActive,
        data_klass: Dinie::Events::LoanActiveData, status: "active",
        data: { id: "ln_1", principal_amount: 5250.5, requested_amount: 5000.0, status: "active" } },
      { type: "loan.payment_received", klass: Dinie::Events::LoanPaymentReceived,
        data_klass: Dinie::Events::LoanPaymentReceivedData, status: "active",
        data: {
          id: "ln_1", payment: { amount: 450.75, installment_number: 1, paid_at: 1_772_791_200 },
          status: "active"
        } },
      { type: "loan.finished", klass: Dinie::Events::LoanFinished,
        data_klass: Dinie::Events::LoanStatusData, status: "finished",
        data: { error: nil, id: "ln_1", status: "finished" } },
      { type: "loan.cancelled", klass: Dinie::Events::LoanCancelled,
        data_klass: Dinie::Events::LoanStatusData, status: "cancelled",
        data: { error: nil, id: "ln_1", status: "cancelled" } },
      { type: "loan.error", klass: Dinie::Events::LoanError,
        data_klass: Dinie::Events::LoanStatusData, status: "error",
        data: {
          error: { code: "disbursement_failed", message: "Bank rejected the transfer" },
          id: "ln_1", status: "error"
        } }
    ]
  end

  # Recursively dump a hydrated event graph back to wire-shaped Hashes/Arrays/scalars (the analogue
  # of the conformance oracle, story 012) — for exact round-trip assertions.
  def deep_h(obj)
    case obj
    when Dinie::Internal::Model then obj.to_h.transform_values { |value| deep_h(value) }
    when Array then obj.map { |item| deep_h(item) }
    else obj
    end
  end

  # ── Signing helpers (mirror `Webhooks.extract`'s verification mechanics) ──────────────────

  # Base64-encode bytes without a trailing newline (the wire form of a `v1` signature).
  def base64_strict(bytes)
    [bytes].pack("m0")
  end

  # The raw HMAC key a secret decodes to (`whsec_` → base64-decoded; otherwise raw bytes).
  def decode_secret(secret)
    return secret.delete_prefix("whsec_").unpack1("m") if secret.start_with?("whsec_")

    secret.b
  end

  # Compute a single `v1,<base64>` signature token over `"{id}.{timestamp}.{body}"`.
  def sign_webhook(secret, webhook_id, timestamp, body)
    digest = OpenSSL::HMAC.digest("SHA256", decode_secret(secret), "#{webhook_id}.#{timestamp}.#{body}".b)
    "v1,#{base64_strict(digest)}"
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength

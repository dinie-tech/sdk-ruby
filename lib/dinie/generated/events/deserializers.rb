# frozen_string_literal: true

require_relative "customer_created"
require_relative "customer_status"
require_relative "customer_denied"
require_relative "customer_kyc_updated"
require_relative "credit_offer"
require_relative "loan_created"
require_relative "loan_signature_received"
require_relative "loan_processing"
require_relative "loan_active"
require_relative "loan_payment_received"
require_relative "loan_status"

# `Dinie::Events::DESERIALIZERS` — the per-type webhook dispatch table (architecture §4.1, RB14).
# Hand-authored in V0.3 to mirror future generator output (`EVENT_DESERIALIZERS` in `sdk-js`
# `src/generated/events/index.ts` @ `19c9bca`); regenerated in V0.5.
#
# ── The forcing-function of openapi-completude (§4.1) ──
# `runtime/webhooks.rb` looks up `DESERIALIZERS[raw[:type]]` AFTER verifying the signature, turning
# the verified snake-native body into the typed event member. A `type` absent from this table has
# no entry, so `extract` raises {Dinie::UnknownWebhookEventError} (never a blind cast). The table is
# the controlled `runtime → generated` reference (architecture §4): editing the event surface
# without updating this table breaks the dispatch specs — the Ruby analogue of the TS
# `Record<WebhookEventType, …>` exhaustiveness that fails `tsc`.
#
# ── 15 entries from 11 schemas (frozen surface §"events") ──
# 8×1 single-type schemas + CustomerStatus(2) + CreditOffer(2) + LoanStatus(3). Multi-type schemas
# point several `type` keys at distinct event classes that share one `*Data` model; each class pins
# its own `type` literal, so the returned member is exact (the key guarantees the right class runs).
#
# ── comparison.md (§2.5) ──
# Table-driven dispatch `type → lambda` (Ruby `Hash`) vs `Record` (TS) → COMMON in structure; the
# verification mechanics (Standard Webhooks v1, HMAC-SHA256, constant-time) are COMMON. The
# discrimination CONSTRUCT (`case/when` in KYC, `Hash` lookup here) is the per-language SPECIFIC axis.
module Dinie
  module Events
    # Per-type webhook deserializers keyed by the event `type` string. Frozen; 15 entries.
    DESERIALIZERS = {
      "customer.created" => ->(raw) { CustomerCreated.deserialize(raw) },
      "customer.under_review" => ->(raw) { CustomerUnderReview.deserialize(raw) },
      "customer.active" => ->(raw) { CustomerActive.deserialize(raw) },
      "customer.denied" => ->(raw) { CustomerDenied.deserialize(raw) },
      "customer.kyc_updated" => ->(raw) { CustomerKycUpdated.deserialize(raw) },
      "credit_offer.available" => ->(raw) { CreditOfferAvailable.deserialize(raw) },
      "credit_offer.expired" => ->(raw) { CreditOfferExpired.deserialize(raw) },
      "loan.created" => ->(raw) { LoanCreated.deserialize(raw) },
      "loan.signature_received" => ->(raw) { LoanSignatureReceived.deserialize(raw) },
      "loan.processing" => ->(raw) { LoanProcessing.deserialize(raw) },
      "loan.active" => ->(raw) { LoanActive.deserialize(raw) },
      "loan.payment_received" => ->(raw) { LoanPaymentReceived.deserialize(raw) },
      "loan.finished" => ->(raw) { LoanFinished.deserialize(raw) },
      "loan.cancelled" => ->(raw) { LoanCancelled.deserialize(raw) },
      "loan.error" => ->(raw) { LoanError.deserialize(raw) }
    }.freeze
  end
end

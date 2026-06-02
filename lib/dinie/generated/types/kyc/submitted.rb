# frozen_string_literal: true

require_relative "../../../runtime/model"
require_relative "common"

# KYC *submitted-evidence* type (architecture §6.3, §3.4-equiv). Hand-authored in V0.3; ports
# `sdk-js` `src/generated/types/kyc/submitted.ts` (@ `19c9bca`). Each piece of submitted evidence
# records its `evidence_type` const, the uploaded `attachments`, and the review outcome
# (`review_status` / `review_reason`).
#
# ── DS-FAMILY (uniform-variant family → one model) ──
# The ten openapi `*Submitted` schemas (`IdentityCnhSubmitted`, `IdentityRgSubmitted`,
# `SelfieSubmitted`, `ProofOfAddressSubmitted`, `CompanyDocumentSubmitted`, `EiMeiDocumentsSubmitted`,
# `IncomeStatementSubmitted`, `ArticlesOfAssociationSubmitted`, `EireliIncorporationStatementSubmitted`,
# `EmailSubmitted`) are STRUCTURALLY IDENTICAL — they differ only by the `evidence_type` const
# literal. TS captures that with one generic `KycSubmitted<E>` + a type alias per variant. Ruby has
# no generics and no literal-union type, so the family collapses to ONE concrete {Kyc::Submitted}
# class carrying `evidence_type` as a plain `String`; the per-variant literal lives in the RBS
# union (story 013) and is documented here. ONE uniform deserializer serves every variant.
#
# ── DS-COLLAPSE (oneOf of arrays with one item shape) ──
# `IdentityCnhSubmitted.attachments` is, in the openapi, a `oneOf` of two ARRAY schemas (physical
# CNH = 2 items `front`/`back`; digital CNH = 1 item `file`). They differ only in cardinality + the
# item `attachment_type` enum — the ITEM shape (`{attachment_type, submitted_at}`) is identical, so
# `attachments` is uniformly `Array<Kyc::Attachment>`; cardinality/enum are doc-only constraints.
#
# ── DS-IMPLICIT (oneOf without an explicit discriminator) ──
# `IdentityRequirement.submitted` is a `oneOf` of CNH | RG with NO `discriminator` block in the
# openapi — UNLIKE `KycRequirement` and the upload union, which both carry an explicit
# `discriminator`. The members still each have a `const evidence_type` (`cnh` / `rg`), so the SDK
# falls back to that const as the discriminator ({deserialize_identity_submitted}). ⚠️ Candidate
# openapi PR **P6** (add an explicit `discriminator: evidence_type` to this oneOf) — NOT authorized
# this round; the implicit-const fallback is sound and tracked.
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports only the runtime model base and the sibling `common` leaf. The
# `deserialize*` methods are the internal hydrate path consumed by `./requirements.rb` and
# conformance (story 012).
module Dinie
  module Kyc
    # Submitted evidence against a requirement (DS-FAMILY — one shape for all ten variants). Carries
    # the uploaded `attachments`, the `evidence_type` discriminant const (as a `String`), and the
    # review outcome.
    class Submitted < Internal::Model
      # R-ORDER: alphabetical. `attachments` → `Array<Kyc::Attachment>`; `review_reason` →
      # `String | nil` (required-nullable); `review_status` ∈ {Kyc::ReviewStatus}.
      attribute :attachments, :evidence_type, :review_reason, :review_status

      # Hydrate a wire `*Submitted` (symbol-keyed Hash). One uniform body for every variant
      # (DS-FAMILY): map the attachments into {Kyc::Attachment}, copy the const `evidence_type`,
      # carry the review fields through (R-EXPLICIT).
      #
      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [Submitted]
      def self.deserialize(raw)
        new(
          attachments: raw[:attachments].map { |item| Attachment.deserialize(item) },
          evidence_type: raw[:evidence_type],
          review_reason: raw[:review_reason],
          review_status: raw[:review_status]
        )
      end
    end

    # Hydrate any non-identity `*Submitted` — the uniform DS-FAMILY path. Delegates to
    # {Submitted.deserialize}.
    #
    # @param raw [Hash{Symbol => Object}] the wire object
    # @return [Submitted]
    def self.deserialize_submitted(raw)
      Submitted.deserialize(raw)
    end

    # Hydrate the identity `submitted` oneOf by dispatching on the const `evidence_type` (DS-IMPLICIT
    # — no explicit discriminator in the openapi). `cnh` and `rg` both hydrate to the uniform
    # {Submitted} (DS-FAMILY); an unmapped value raises a clear {Dinie::Error} ({dispatch_error}).
    # The dispatch exists to VALIDATE the discriminator, not to branch the shape.
    #
    # @param raw [Hash{Symbol => Object}] the wire object
    # @return [Submitted]
    # @raise [Dinie::Error] when `evidence_type` is neither `cnh` nor `rg`
    def self.deserialize_identity_submitted(raw)
      case raw[:evidence_type]
      when "cnh", "rg" then Submitted.deserialize(raw)
      else raise dispatch_error("IdentitySubmitted", "evidence_type", raw[:evidence_type])
      end
    end
  end
end

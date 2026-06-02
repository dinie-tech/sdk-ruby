# frozen_string_literal: true

# KYC block barrel (architecture §6.3, §3.4-equiv) — required by the types index (`../types.rb`).
# The KYC subsystem is the project's complexity HOTSPOT (~41 types modeled as discriminated unions)
# and the `comparison.md` canary: the same `oneOf` + `discriminator` that emits a TS `switch` emits
# a Ruby `case/when` here. Hand-authored in V0.3; ports `sdk-js` `src/generated/types/kyc/`
# (@ `19c9bca`), regenerated in V0.5.
#
# Split by concern (the dispatch lives with its union), ordered deps-first:
#   * `kyc/common`        leaf types — ReviewStatus/SubjectType, Subject, Attachment, dispatch_error.
#   * `kyc/submitted`     the uniform `Submitted` evidence family + the identity CNH|RG dispatch.
#   * `kyc/requirements`  the nine `*Requirement` variants + the `KycRequirement` dispatch.
#   * `kyc/attachment`    `AttachmentResponse` (the upload response wrapping a requirement).
#   * `kyc/uploads`       the upload request serializer + the multipart field-map (`UploadForm`).
#
# ── Determinism shapes (the §6.3 reference the V0.5 generator emits, story 014 classifies) ──
#   DS-DISCRIMINATED          oneOf + explicit discriminator → base + subclasses + value `case/when`
#                             dispatch (KycRequirement / KycUpload). Canary vs the TS `switch`.
#   DS-IMPLICIT               oneOf WITHOUT a discriminator → fall back to the const field
#                             (IdentityRequirement.submitted CNH|RG, const `evidence_type`). ⚠️ P6.
#   DS-FAMILY                 N schemas differing only by a const → ONE model + ONE deserializer
#                             (the ten `*Submitted` → `Kyc::Submitted`).
#   DS-COLLAPSE               oneOf of arrays with one item shape → `Array<Kyc::Attachment>`
#                             (CnhPhysical 2 / CnhDigital 1).
#   DS-CONST-ID / DS-SUBJECT  const vs pattern id; presence-driven `subject` (person vs company).
#   DS-MULTIPART              multipart request oneOf → field-map + optional binary `file`
#                             (`UploadForm`); the Ruby runtime encodes it (no V0.2 GAP).
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Requires the runtime model base (via the leaves) and nothing else from
# `runtime/`. The transport wrapper for uploads ({Dinie::Internal::Multipart}) lives in `runtime/`.

require_relative "kyc/common"
require_relative "kyc/submitted"
require_relative "kyc/requirements"
require_relative "kyc/attachment"
require_relative "kyc/uploads"

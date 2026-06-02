# frozen_string_literal: true

require_relative "../../../runtime/model"

# KYC shared leaf types + the discriminated-union dispatch error (architecture §6.3, §3.4-equiv).
# Hand-authored in V0.3 to mirror what the V0.5 generator will emit; ports `sdk-js`
# `src/generated/types/kyc/common.ts` (@ `19c9bca`). Follows the hydrate/dump convention of
# `../customer.rb` (the exemplar) and its four rules (R-EXPLICIT / R-ORDER alphabetical /
# R-OPTIONAL / R-EPOCH).
#
# These are the leaves every requirement/submitted variant reuses, so they live in one place:
#   * {Kyc::ReviewStatus} / {Kyc::SubjectType}  — value catalogs for the two KYC enums.
#   * `ReviewReason`                            — wire `type: [string, 'null']` → `String | nil`,
#                                                  required-but-nullable (no enum, no class — a
#                                                  plain attribute carried as-is).
#   * {Kyc::Subject}                            — who a person-specific requirement is about.
#   * {Kyc::Attachment}                         — one uploaded-evidence slot
#                                                  (`{attachment_type, submitted_at}`).
#   * {Kyc.dispatch_error}                      — the shared error for an unknown discriminator.
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports only the runtime model base; no transport. Public surface lives
# under `Dinie::Kyc::*`; the `deserialize` class methods are the internal hydrate path consumed by
# the sibling KYC modules, the customers resource, `../customer.rb`, and conformance (story 012).
module Dinie
  # The KYC subsystem (architecture §6.3, §3.4-equiv) — the project's complexity HOTSPOT (~41
  # types) and the `comparison.md` canary. Requirement/submitted/upload families are discriminated
  # unions; the dispatch is a value-driven `case/when` (Ruby) mirroring the TS `switch`.
  module Kyc
    # Review state of a submitted piece of KYC evidence — `components.schemas.ReviewStatus`
    # (openapi @ 3fcfd83). Surfaced as a plain `String`; this module names the values (the
    # Ruby-specific affordance — see `../enums.rb`).
    module ReviewStatus
      # Awaiting review.
      PENDING = "pending"
      # Approved.
      ACCEPTED = "accepted"
      # Rejected — the partner must resubmit.
      REJECTED = "rejected"
      # Every valid value, in contract order.
      ALL = [PENDING, ACCEPTED, REJECTED].freeze
    end

    # Subject kind for a person-specific requirement — `components.schemas.KycSubject.subject_type`.
    module SubjectType
      # The customer themselves.
      APPLICANT = "applicant"
      # A director/shareholder of the company.
      CO_OWNER = "co_owner"
      # Every valid value, in contract order.
      ALL = [APPLICANT, CO_OWNER].freeze
    end

    # Identifies who a requirement is about — the applicant themselves or a company co-owner.
    # Present only on person-specific requirements (identity / selfie / proof-of-address / email).
    class Subject < Internal::Model
      # R-ORDER: alphabetical.
      attribute :id, :name, :subject_type

      # Hydrate a wire {Subject} (symbol-keyed Hash). Explicit per-field (R-EXPLICIT).
      #
      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [Subject]
      def self.deserialize(raw)
        new(
          id: raw[:id],
          name: raw[:name],
          subject_type: raw[:subject_type]
        )
      end
    end

    # One uploaded-evidence slot within a `*Submitted`. Every submitted variant's `attachments`
    # array is a list of these. The openapi defines the item inline per variant, but the shape is
    # uniform (`{attachment_type, submitted_at}`), so the SDK emits ONE leaf type they all reference.
    #
    # `attachment_type` is intentionally a broad `String`: each variant constrains it to its own
    # enum/const (`front`/`back`/`file`/`photo`/`email`/`ei_registration_requirement`/`ccmei`),
    # documented at each requirement. `submitted_at` stays epoch `Integer | nil` (R-EPOCH) — `nil`
    # when a slot is not yet uploaded.
    class Attachment < Internal::Model
      # R-ORDER: alphabetical.
      attribute :attachment_type, :submitted_at

      # Hydrate a wire {Attachment} (symbol-keyed Hash). `submitted_at` stays epoch `Integer | nil`.
      #
      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [Attachment]
      def self.deserialize(raw)
        new(
          attachment_type: raw[:attachment_type],
          submitted_at: raw[:submitted_at]
        )
      end
    end

    # Build the error raised when a discriminated-union dispatch hits a value not in the openapi
    # `oneOf` mapping (a member the contract never declared). One shared helper so every KYC
    # dispatch ({deserialize_requirement}, {deserialize_identity_submitted}, {serialize_upload})
    # fails the same template-emittable way — a clear, typed {Dinie::Error}, never a silent `nil`.
    #
    # @param union [String] the union's name, e.g. `"KycRequirement"`
    # @param discriminator [String] the discriminator property, e.g. `"requirement_type"`
    # @param value [Object] the unrecognized wire value
    # @return [Dinie::Error]
    def self.dispatch_error(union, discriminator, value)
      Dinie::Error.new(
        "Unknown #{union} #{discriminator}: #{value.inspect}. This discriminator value is not " \
        "declared in the openapi oneOf mapping — the SDK and contract are out of sync."
      )
    end
  end
end

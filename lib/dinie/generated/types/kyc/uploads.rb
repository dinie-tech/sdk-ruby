# frozen_string_literal: true

require_relative "../../../runtime/model"
require_relative "common"

# KYC *upload* request serialization + the `KycUpload` discriminated union (architecture §6.3,
# §3.4-equiv, §14). Hand-authored in V0.3; ports `sdk-js` `src/generated/types/kyc/uploads.ts`
# (@ `19c9bca`). These are the request variants of `POST /customers/{id}/kyc-attachments` — ten
# document/data kinds, sent as `multipart/form-data` and discriminated by an EXPLICIT
# `discriminator: evidence_type` (the path's `requestBody` oneOf, openapi @ `3fcfd83`).
#
# ── DS-DISCRIMINATED-REQUEST (mirror of the response rule, applied to a request) ──
# Same rule as {Kyc.deserialize_requirement}, applied to a REQUEST union and emitted as a serializer:
# {Kyc.serialize_upload} is a `case evidence_type` whose `when` values ARE the openapi
# `discriminator.mapping` keys, raising {Kyc.dispatch_error} on an unmapped value. Table-driven, not
# bespoke. Following the Ruby idiom (RB4 — keyword arguments, no request-object type), the union
# members are NOT ten classes; they are the kwargs the caller passes to
# `customers.kyc_attachments.create(customer_id, **upload)`, dispatched here by `evidence_type`.
#
# ── DS-MULTIPART (binary `file` vs scalar `value`) ──
# The request content type is `multipart/form-data`, not JSON. Nine variants carry a binary `file`
# (openapi `format: binary`); the email variant carries a scalar `value` instead. So a variant
# serializes to a {Kyc::UploadForm}: the snake_case SCALAR fields (`attachment_type`,
# `evidence_type`, `requirement_id`, plus `value` for email — alphabetical, R-ORDER) plus the
# optional binary `file`. The field-map is the deterministic unit of conformance (story 012),
# independent of transport. The runtime wraps it for the wire: the customers resource hands the
# `UploadForm` to {Dinie::Internal::Multipart}, and Faraday's `:multipart` middleware encodes it
# (architecture §10/§14). Unlike the V0.2 TS runtime (JSON-only `serializeBody` — the tracked
# RUNTIME GAP), the Ruby runtime (story 003 + this story's seam) encodes multipart on the wire.
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports only the runtime model base (for {Dinie::Internal::OMIT}) and the
# sibling `common` leaf — NO transport (it stays Faraday-agnostic; {Dinie::Internal::Multipart}
# owns the Faraday parts). {Kyc.serialize_upload} and {Kyc::UploadForm} are the internal serialize
# path consumed by the customers resource and conformance.
module Dinie
  module Kyc
    # The deterministic multipart representation of a KYC upload (DS-MULTIPART): the ordered
    # snake_case scalar form `fields` plus the optional binary `file`. This is what
    # {Kyc.serialize_upload} produces and {Dinie::Internal::Multipart} encodes — the unit of
    # conformance, independent of how the transport frames it. `file` is opaque here (an IO, raw
    # bytes, or a pre-built Faraday part); the runtime wraps it.
    UploadForm = Struct.new(:fields, :file, keyword_init: true)

    # The nine file-bearing upload `evidence_type`s (carry a binary `file`). The tenth — `email` —
    # carries a scalar `value` instead. In openapi mapping order.
    FILE_UPLOAD_EVIDENCE_TYPES = %w[
      cnh rg selfie proof_of_address ccmei ei_mei
      income_statement articles_of_association eireli_incorporation_statement
    ].freeze

    # Serialize a KYC upload to its {UploadForm} by dispatching on the explicit `evidence_type`
    # discriminator (DS-DISCRIMINATED-REQUEST). The nine file variants share one shape (scalar
    # fields + the binary `file`); the email variant maps `value` to a scalar field instead. An
    # unmapped `evidence_type` raises {dispatch_error}. Whether a variant carries `file` (binary) or
    # `value` (scalar) is derivable from the schema (`format: binary` vs a plain string), so the
    # V0.5 generator reproduces this table from the openapi alone.
    #
    # @param evidence_type [String] the document/data kind (the discriminator)
    # @param requirement_id [String] the requirement this upload fills (`identity_…`, `company_document`, …)
    # @param attachment_type [String] the slot kind (`front`/`back`/`file`/`photo`/`email`/…)
    # @param file [Object, Internal::OMIT] the binary file (required for the nine file variants)
    # @param value [String, Internal::OMIT] the scalar value (required for the `email` variant)
    # @return [UploadForm] the scalar field-map + optional file
    # @raise [Dinie::Error] when `evidence_type` is unknown, or the variant's required part is missing
    def self.serialize_upload(evidence_type:, requirement_id:, attachment_type:, file: Internal::OMIT,
                              value: Internal::OMIT)
      # R-ORDER: scalar fields alphabetical.
      fields = { attachment_type:, evidence_type:, requirement_id: }
      case evidence_type
      when *FILE_UPLOAD_EVIDENCE_TYPES
        if Internal.omitted?(file)
          raise Dinie::Error, "KYC upload evidence_type=#{evidence_type.inspect} requires a `file:`"
        end

        UploadForm.new(fields:, file:)
      when "email"
        raise Dinie::Error, "KYC upload evidence_type=\"email\" requires a `value:`" if Internal.omitted?(value)

        UploadForm.new(fields: fields.merge(value:), file: nil)
      else
        raise dispatch_error("KycUpload", "evidence_type", evidence_type)
      end
    end
  end
end

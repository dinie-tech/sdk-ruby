# frozen_string_literal: true

require_relative "../../../runtime/model"
require_relative "requirements"

# `Kyc::AttachmentResponse` — the body returned by `POST /customers/{id}/kyc-attachments`
# (architecture §6.3, §3.2). Hand-authored in V0.3; ports `sdk-js`
# `src/generated/types/kyc/attachment.ts` (@ `19c9bca`). Wraps the FULL requirement state after the
# upload, so the caller sees the new review status without a follow-up read.
#
# Read-only model (a response body) → `deserialize` only, no serializer (the convention from
# `../customer.rb`). Its `requirement` is a {Kyc::Requirement}, so the deserializer delegates to
# {Kyc.deserialize_requirement} (the discriminated dispatch).
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports the runtime model base and the sibling requirements module. The
# model is public surface (`Dinie::Kyc::AttachmentResponse`); `deserialize` is the internal hydrate
# path consumed by the customers resource (`kyc_attachments.create`) and conformance (story 012).
module Dinie
  module Kyc
    # Response from uploading a KYC attachment — the post-upload requirement state.
    class AttachmentResponse < Internal::Model
      # R-ORDER: alphabetical. `id` → `ka_…`; `requirement` → a {Kyc::Requirement} variant;
      # `uploaded_at` → epoch `Integer` (R-EPOCH).
      attribute :id, :requirement, :uploaded_at

      # Hydrate a wire {AttachmentResponse} (symbol-keyed Hash). `requirement` recurses through the
      # discriminated {Kyc.deserialize_requirement}; `uploaded_at` stays epoch `Integer`.
      #
      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [AttachmentResponse]
      def self.deserialize(raw)
        new(
          id: raw[:id],
          requirement: Kyc.deserialize_requirement(raw[:requirement]),
          uploaded_at: raw[:uploaded_at]
        )
      end
    end
  end
end

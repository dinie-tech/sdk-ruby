# frozen_string_literal: true

require "securerandom"

module Dinie
  module Internal
    # Idempotency-Key generation (architecture §10, RB15; mirrors `sdk-js` `idempotency.ts`).
    #
    # One job: mint a fresh auto-generated key. The `dinie-sdk-retry-` prefix lets the Dinie
    # backend tell an SDK-generated key apart from a partner-supplied one.
    #
    # The *policy* around the key lives in {HttpClient} (story 003), NOT here:
    #   - only non-GET writes get one (auto on POST/PATCH),
    #   - the key is generated ONCE before the retry loop, so every attempt of the same logical
    #     request reuses it (a retry must never create a duplicate resource),
    #   - a caller can override it via `request_options[:idempotency_key]`,
    #   - the whole behavior can be opted out globally with `idempotency: false`.
    #
    # Runtime-internal: consumed directly by {HttpClient}, not part of the public surface.
    module Idempotency
      # Prefix marking a key as SDK-auto-generated (vs. partner-supplied) on the backend.
      KEY_PREFIX = "dinie-sdk-retry-"

      module_function

      # A fresh auto-generated Idempotency-Key: `dinie-sdk-retry-<uuid v4>`.
      #
      # @return [String]
      def generate_key
        "#{KEY_PREFIX}#{SecureRandom.uuid}"
      end
    end
  end
end

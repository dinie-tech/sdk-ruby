# frozen_string_literal: true

require "set"
require "faraday"

module Dinie
  module Internal
    # Retry policy — pure decision + delay functions (no I/O, no state). The retry loop itself
    # — sleeping, attempt counting, the `X-Dinie-Retry-Count` header, the 401 one-shot re-auth
    # — lives in {HttpClient} (architecture §10, RB15). Mirrors `sdk-js` `retry.ts` so the two
    # SDKs share the exact same backoff/jitter/status-set behavior (the `comparison.md` axis).
    #
    # Runtime-internal: imported directly by {HttpClient}, not part of the public surface. The
    # public `Retry-After` parser lives separately as {Dinie.parse_retry_after} (story 002).
    module Retry
      # HTTP status codes the SDK retries (V0.2 freeze decision; architecture §10).
      #
      # Exactly `{408, 429, 500, 502, 503, 504}`, plus timeouts/connection errors (handled by
      # {retryable_network_error?}). `410` (gone) **never** retries, and neither does a `409`
      # (Dinie semantic conflict) except the `idempotency_key_in_use` one
      # ({idempotency_key_in_use?}); `401` is a one-shot re-auth handled in {HttpClient},
      # orthogonal to this set.
      # `500` is safe to retry on a non-GET because the stable `X-Idempotency-Key` (minted once
      # before the loop) guarantees a retry never creates a duplicate resource.
      RETRYABLE_STATUS = Set[408, 429, 500, 502, 503, 504].freeze

      # Initial backoff, in seconds (the `attempt = 0` base before jitter).
      INITIAL_BACKOFF_SECONDS = 0.5
      # Backoff ceiling, in seconds (reached at `attempt = 4`).
      MAX_BACKOFF_SECONDS = 8
      # Subtractive jitter fraction — the delay is reduced by up to this share.
      JITTER_RATIO = 0.25
      # Problem `code` of the 409 sent while another request with the same idempotency key is
      # still running.
      IDEMPOTENCY_KEY_IN_USE_CODE = "idempotency_key_in_use"

      # Faraday transport errors (no HTTP response) worth retrying: a request timeout and a
      # connection failure (DNS/refused/reset). Anything else propagates as a connection error.
      RETRYABLE_NETWORK_ERRORS = [Faraday::TimeoutError, Faraday::ConnectionFailed].freeze

      module_function

      # True only for the retryable status set (`{408, 429, 500, 502, 503, 504}`).
      #
      # @param status [Integer]
      # @return [Boolean]
      def should_retry?(status)
        RETRYABLE_STATUS.include?(status)
      end

      # True for the 409 the API sends while a request with the same idempotency key is still
      # running. It is retried like a `429`: same key, after its `Retry-After`. Any other 409 is a
      # final answer.
      #
      # @param status [Integer]
      # @param code [String, nil] the Problem Details `code` of the response
      # @return [Boolean]
      def idempotency_key_in_use?(status, code)
        status == 409 && code == IDEMPOTENCY_KEY_IN_USE_CODE
      end

      # Whether a thrown transport error (no HTTP response) is worth retrying: a timeout or a
      # connection failure. Keys off the Faraday error class, never the message.
      #
      # @param error [Exception]
      # @return [Boolean]
      def retryable_network_error?(error)
        RETRYABLE_NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }
      end

      # Seconds to wait before the next attempt.
      #
      # A parseable `Retry-After` / `Retry-After-Ms` wins (already clamped to `[0, 60]` by
      # {Dinie.parse_retry_after}). Otherwise: exponential backoff `min(0.5 · 2^attempt, 8) s`
      # minus up to 25% subtractive jitter via `rand` (assert the band in specs, not the value).
      #
      # @param attempt [Integer] zero-based attempt index just completed
      # @param retry_after [String, Array<String>, nil] the response `Retry-After` header
      # @param retry_after_ms [String, Array<String>, nil] the response `Retry-After-Ms` header
      # @return [Float] seconds to sleep
      def retry_delay(attempt, retry_after: nil, retry_after_ms: nil)
        from_header = Dinie.parse_retry_after(retry_after, retry_after_ms: retry_after_ms)
        return from_header unless from_header.nil?

        base = [INITIAL_BACKOFF_SECONDS * (2**attempt), MAX_BACKOFF_SECONDS].min
        base * (1 - (JITTER_RATIO * rand))
      end
    end
  end
end

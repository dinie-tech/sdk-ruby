# frozen_string_literal: true

require "json"
require "openssl"

require_relative "errors"

module Dinie
  # `Dinie::Webhooks.extract` — webhook verification + per-type deserialization, a module-function
  # (RB11, architecture §8, §18.2). Implements the Standard Webhooks v1 contract Dinie inherited:
  #
  #     signed_payload = "{webhook-id}.{webhook-timestamp}.{body}"
  #     expected       = base64(HMAC-SHA256(decode_secret(secret), signed_payload))
  #     header         = "v1,<sig1> v1,<sig2>"   # space-separated, rotation-capable
  #
  # `extract` does verification AND deserialization in one call: it reads the three `webhook-*`
  # headers (case-insensitive, symbol/string), enforces a bidirectional timestamp window (replay
  # guard), decodes the secret (`whsec_` → base64), HMAC-SHA256s the signed payload, and compares —
  # in CONSTANT time via {OpenSSL.secure_compare} — against every `v1,<sig>` in the header. Any
  # match → {Dinie::Events::DESERIALIZERS}`[type]` hydrates the snake-native body into the typed
  # {Dinie::Events} member; an unknown `type` → {Dinie::UnknownWebhookEventError}; no match →
  # {Dinie::WebhookSignatureError}. It NEVER returns an unverified event (security by behavior — the
  # name `extract` returns the event, not a boolean).
  #
  # Both `secret` and the signature header accept multiple values, so secret rotation works from
  # either side. Verification needs no OAuth credentials, hence a module-function (not a client
  # method). Mirrors `sdk-js` `src/runtime/webhooks.ts` (@ `19c9bca`), in Ruby (`openssl` stdlib;
  # base64 via `String#unpack1("m")` / `Array#pack("m0")` — no extra dependency).
  #
  # ── runtime ↔ generated boundary (controlled inverse import — openapi-SoT, §4) ──
  # The general rule is "runtime/ never imports generated/". `webhooks.rb` is one of two declared
  # exceptions (the other is `http.rb → ERROR_REGISTRY`). The webhook event catalog's SoT is
  # `openapi.yaml` (`webhooks:`), so the typed members AND the {Dinie::Events::DESERIALIZERS} table
  # live in `generated/events/`. This module references the table at call time; the barrel
  # (`lib/dinie.rb`) loads `generated/events` before any call. The reference is the forcing-function:
  # an event not in openapi is not in `generated/events`, not in the table, so `extract` raises
  # {Dinie::UnknownWebhookEventError} — forcing the contract conversation.
  #
  # ── Header normalization (deferred decision §21.5 — RESOLVED: case-insensitive + symbol/string) ──
  # Standard Webhooks headers are lowercase dashed (`webhook-id`). Inbound frameworks vary in
  # capitalization, so the lookup is case-insensitive and accepts both String and Symbol keys. The
  # partner passes a Hash keyed by the `webhook-*` names; framework env normalization (Rack's
  # `HTTP_WEBHOOK_ID`) is the partner's responsibility (a framework adapter is out of scope, §1):
  #
  #   # Rails:   Dinie::Webhooks.extract(headers: request.headers.to_h, body: request.raw_post, secret:)
  #   # Sinatra: Dinie::Webhooks.extract(headers: { "webhook-id" => request.env["HTTP_WEBHOOK_ID"],
  #   #            "webhook-timestamp" => request.env["HTTP_WEBHOOK_TIMESTAMP"],
  #   #            "webhook-signature" => request.env["HTTP_WEBHOOK_SIGNATURE"] }, body: request.body.read, secret:)
  #   # Rack:    headers = env.select { |k, _| k.start_with?("HTTP_") }
  #   #            .transform_keys { |k| k.delete_prefix("HTTP_").downcase.tr("_", "-") }
  module Webhooks
    # Default replay tolerance, in seconds (5 minutes), applied in both directions.
    DEFAULT_TOLERANCE_SECONDS = 300
    # Secrets carrying this prefix are base64-encoded; the remainder is decoded before HMAC.
    WHSEC_PREFIX = "whsec_"
    # Only `v1` signature tokens are honored.
    SIGNATURE_VERSION = "v1"

    module_function

    # Verify a Standard Webhooks v1 payload and return the deserialized, typed event — a
    # {Dinie::Events} member straight from openapi (`generated/events/`), hydrated per type so the
    # snake-native surface is honest. It NEVER returns an unverified event.
    #
    # @param headers [Hash] inbound HTTP headers (case-insensitive lookup of the `webhook-*` trio)
    # @param body [String] the RAW request body, exactly as received, BEFORE `JSON.parse`
    # @param secret [String, Array<String>] signing secret(s); `whsec_`-prefixed → base64. An Array
    #   tries each secret (rotation)
    # @param tolerance_seconds [Integer] replay window in seconds, applied in both directions
    # @return [Dinie::Events::WebhookEventBase] the verified, typed event member
    # @raise [Dinie::WebhookTimestampError] the timestamp header is missing, malformed, or outside
    #   the tolerance window (too old OR too far in the future)
    # @raise [Dinie::WebhookSignatureError] a required header is missing, no usable secret was
    #   supplied, or no signature in the header matched
    # @raise [Dinie::UnknownWebhookEventError] the signature verified but the payload's `type` is
    #   not in the openapi event catalog
    def extract(headers:, body:, secret:, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS)
      webhook_id = required_header(headers, "webhook-id", Dinie::WebhookSignatureError)
      timestamp = required_header(headers, "webhook-timestamp", Dinie::WebhookTimestampError)
      signature = required_header(headers, "webhook-signature", Dinie::WebhookSignatureError)

      verify_timestamp!(timestamp, tolerance_seconds)
      verify_signature!(signed_payload(webhook_id, timestamp, body), secret, signature)
      deserialize_verified_event(body)
    end

    # @api private
    # Build the byte-faithful signed payload `"{id}.{timestamp}.{body}"` (binary-concatenated so a
    # non-UTF-8 body never raises an encoding error).
    def signed_payload(webhook_id, timestamp, body)
      "#{webhook_id}.#{timestamp}.".b + body.to_s.b
    end

    # @api private
    # Fetch a required header or raise `error_class`. Missing and empty both fail.
    def required_header(headers, name, error_class)
      value = lookup_header(headers, name)
      return value unless value.nil? || value == ""

      raise error_class, "Missing required webhook header: #{name}."
    end

    # @api private
    # Case-insensitive, symbol/string single-value header lookup (§21.5). A list value (rare) yields
    # its first element.
    def lookup_header(headers, name)
      value = fetch_header(headers, name)
      value.is_a?(Array) ? value.first : value
    end

    # @api private
    def fetch_header(headers, name)
      return headers[name] if headers.key?(name)
      return headers[name.to_sym] if headers.key?(name.to_sym)

      target = name.downcase
      headers.each { |key, value| return value if key.to_s.downcase == target }
      nil
    end

    # @api private
    # Enforce the bidirectional replay window: reject a malformed, too-old, or too-far-future
    # timestamp.
    def verify_timestamp!(timestamp, tolerance_seconds)
      seconds = Integer(timestamp.to_s.strip, 10, exception: false)
      raise Dinie::WebhookTimestampError, "Invalid webhook timestamp: #{timestamp.inspect}." if seconds.nil?

      skew = Time.now.to_i - seconds
      raise Dinie::WebhookTimestampError, "Webhook timestamp is too old." if skew > tolerance_seconds
      return unless skew < -tolerance_seconds

      raise Dinie::WebhookTimestampError, "Webhook timestamp is too far in the future."
    end

    # @api private
    # Raise unless any (secret, signature) pair matches (constant-time, multi-sig rotation).
    def verify_signature!(payload, secret, signature_header)
      secrets = normalize_secrets(secret)
      raise Dinie::WebhookSignatureError, "No webhook secret provided." if secrets.empty?
      return if signatures_match?(payload, secrets, parse_signature_header(signature_header))

      raise Dinie::WebhookSignatureError,
            "No matching webhook signature found; the payload may have been tampered with."
    end

    # @api private
    def normalize_secrets(secret)
      Array(secret).select { |candidate| candidate.is_a?(String) && !candidate.empty? }
    end

    # @api private
    # Split the `webhook-signature` header into decoded `v1` signatures. Space-separated
    # `v1,<base64>` tokens; non-`v1` and malformed tokens are dropped.
    def parse_signature_header(header)
      header.split.filter_map do |token|
        version, separator, value = token.partition(",")
        next if separator.empty? || value.empty? || version != SIGNATURE_VERSION

        value.unpack1("m")
      end
    end

    # @api private
    # True when any (secret, signature) pair matches. {OpenSSL.secure_compare} is constant-time and
    # safe on unequal-length inputs (it digests both first), so no length guard is needed.
    def signatures_match?(payload, secrets, provided_signatures)
      secrets.any? do |secret|
        expected = OpenSSL::HMAC.digest("SHA256", decode_secret(secret), payload)
        provided_signatures.any? { |candidate| OpenSSL.secure_compare(candidate, expected) }
      end
    end

    # @api private
    # `whsec_`-prefixed secrets are base64; everything else is treated as raw bytes.
    def decode_secret(secret)
      return secret.delete_prefix(WHSEC_PREFIX).unpack1("m") if secret.start_with?(WHSEC_PREFIX)

      secret.b
    end

    # @api private
    # Deserialize a VERIFIED body per type (reached only after a signature matched, so the bytes are
    # authentic). Dispatch is table-driven through {Dinie::Events::DESERIALIZERS}; a `type` absent
    # from the catalog raises {Dinie::UnknownWebhookEventError} (forces the contract conversation).
    def deserialize_verified_event(body)
      raw = JSON.parse(body, symbolize_names: true)
      event_type = raw[:type]
      deserializer = event_type.is_a?(String) ? Dinie::Events::DESERIALIZERS[event_type] : nil
      raise Dinie::UnknownWebhookEventError, event_type.to_s if deserializer.nil?

      deserializer.call(raw)
    end
  end
end

# frozen_string_literal: true

require "json"

require_relative "../support/webhook_event_fixtures"

# `Dinie::Webhooks.extract` specs (story 011 — the second V0.3 hotspot, RB11/§8/§18.2). The
# exhaustive webhook tier: Standard Webhooks v1 verification (valid/invalid/rotated/tampered/
# missing-header), the bidirectional timestamp window, case-insensitive symbol/string header lookup,
# constant-time compare, and per-type dispatch of all 15 events through {Dinie::Events::DESERIALIZERS}
# AFTER verification. Security-by-behavior: NO failure path returns an object. Fixtures:
# {WebhookEventFixtures}. `WebMock.disable_net_connect!` holds (extract makes no network call).
RSpec.describe Dinie::Webhooks do
  include WebhookEventFixtures

  # A raw 24-byte signing key, exposed as a `whsec_`-prefixed (base64) secret — the production shape.
  let(:raw_key) { "0123456789abcdef01234567" }
  let(:secret) { "whsec_#{base64_strict(raw_key)}" }
  let(:webhook_id) { "msg_2KWPBgLlAfxdpx2AI54pPJ85f4W" }
  let(:timestamp) { Time.now.to_i.to_s }
  let(:loan_active_entry) { webhook_event_table.find { |row| row[:type] == "loan.active" } }
  let(:body) { JSON.generate(webhook_envelope(type: "loan.active", data: loan_active_entry[:data])) }
  let(:signature) { sign_webhook(secret, webhook_id, timestamp, body) }
  let(:headers) do
    { "webhook-id" => webhook_id, "webhook-timestamp" => timestamp, "webhook-signature" => signature }
  end

  describe "valid signature → typed event" do
    it "verifies and returns the typed, snake-native event" do
      event = described_class.extract(headers:, body:, secret:)

      expect(event).to be_a(Dinie::Events::LoanActive)
      expect(event.type).to eq("loan.active")
      expect(event.data.principal_amount).to eq(5250.5)
    end

    it "accepts a raw (non-`whsec_`) secret too" do
      raw_secret = "a-plain-shared-secret"
      sig = sign_webhook(raw_secret, webhook_id, timestamp, body)
      headers_raw = headers.merge("webhook-signature" => sig)

      expect(described_class.extract(headers: headers_raw, body:, secret: raw_secret))
        .to be_a(Dinie::Events::LoanActive)
    end

    it "dispatches each of the 15 verified types to the right event class (discrimination matrix)" do
      webhook_event_table.each do |entry|
        wire_body = JSON.generate(webhook_envelope(type: entry[:type], data: entry[:data]))
        sig = sign_webhook(secret, webhook_id, timestamp, wire_body)
        hdrs = headers.merge("webhook-signature" => sig)

        event = described_class.extract(headers: hdrs, body: wire_body, secret:)

        expect(event).to be_a(entry[:klass]), "extract mis-dispatched #{entry[:type]}"
        expect(event.type).to eq(entry[:type])
      end
    end
  end

  describe "signature failures → WebhookSignatureError (never an object)" do
    it "rejects a signature computed with the wrong secret" do
      bad_sig = sign_webhook("whsec_#{base64_strict("wrong-key-wrong-key-wxyz")}", webhook_id, timestamp, body)

      expect { described_class.extract(headers: headers.merge("webhook-signature" => bad_sig), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError, /No matching webhook signature/)
    end

    it "rejects a tampered body (signature no longer matches the bytes)" do
      tampered = body.sub("5250.5", "999999.0")

      expect { described_class.extract(headers:, body: tampered, secret:) }
        .to raise_error(Dinie::WebhookSignatureError)
    end

    it "rejects when the signature header carries no usable v1 token" do
      expect { described_class.extract(headers: headers.merge("webhook-signature" => "v0,deadbeef"), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError)
    end

    it "raises (does not crash) when a provided signature is a different length (constant-time safe)" do
      short_sig = "v1,#{base64_strict("short")}"

      expect { described_class.extract(headers: headers.merge("webhook-signature" => short_sig), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError)
    end

    it "raises when no usable secret is provided" do
      expect { described_class.extract(headers:, body:, secret: "") }
        .to raise_error(Dinie::WebhookSignatureError, /No webhook secret provided/)
      expect { described_class.extract(headers:, body:, secret: []) }
        .to raise_error(Dinie::WebhookSignatureError, /No webhook secret provided/)
    end
  end

  describe "multi-signature rotation (any one match passes)" do
    it "passes when one of several space-separated `v1` signatures matches" do
      multi = "v1,#{base64_strict("not-a-match")} #{signature} v1,#{base64_strict("also-wrong")}"

      expect(described_class.extract(headers: headers.merge("webhook-signature" => multi), body:, secret:))
        .to be_a(Dinie::Events::LoanActive)
    end

    it "passes when one of several rotated secrets matches (secret: Array)" do
      old_secret = "whsec_#{base64_strict("retired-key-retired-keyy")}"

      expect(described_class.extract(headers:, body:, secret: [old_secret, secret]))
        .to be_a(Dinie::Events::LoanActive)
    end

    it "still fails when no signature in a multi-sig header matches" do
      multi = "v1,#{base64_strict("nope-1")} v1,#{base64_strict("nope-2")}"

      expect { described_class.extract(headers: headers.merge("webhook-signature" => multi), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError)
    end
  end

  describe "timestamp window (bidirectional replay guard) → WebhookTimestampError" do
    it "rejects a timestamp older than the tolerance" do
      old = (Time.now.to_i - 1000).to_s
      sig = sign_webhook(secret, webhook_id, old, body)

      expect do
        described_class.extract(headers: headers.merge("webhook-timestamp" => old, "webhook-signature" => sig),
                                body:, secret:)
      end.to raise_error(Dinie::WebhookTimestampError, /too old/)
    end

    it "rejects a timestamp too far in the future" do
      future = (Time.now.to_i + 1000).to_s
      sig = sign_webhook(secret, webhook_id, future, body)

      expect do
        described_class.extract(headers: headers.merge("webhook-timestamp" => future, "webhook-signature" => sig),
                                body:, secret:)
      end.to raise_error(Dinie::WebhookTimestampError, /future/)
    end

    it "rejects a malformed (non-integer) timestamp" do
      expect { described_class.extract(headers: headers.merge("webhook-timestamp" => "not-a-number"), body:, secret:) }
        .to raise_error(Dinie::WebhookTimestampError, /Invalid webhook timestamp/)
    end

    it "honors a custom tolerance_seconds window" do
      old = (Time.now.to_i - 100).to_s
      sig = sign_webhook(secret, webhook_id, old, body)
      hdrs = headers.merge("webhook-timestamp" => old, "webhook-signature" => sig)

      expect { described_class.extract(headers: hdrs, body:, secret:, tolerance_seconds: 30) }
        .to raise_error(Dinie::WebhookTimestampError)
      expect(described_class.extract(headers: hdrs, body:, secret:, tolerance_seconds: 600))
        .to be_a(Dinie::Events::LoanActive)
    end
  end

  describe "missing required headers" do
    it "raises WebhookSignatureError when webhook-id is missing or empty" do
      expect { described_class.extract(headers: headers.except("webhook-id"), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError, /webhook-id/)
      expect { described_class.extract(headers: headers.merge("webhook-id" => ""), body:, secret:) }
        .to raise_error(Dinie::WebhookSignatureError, /webhook-id/)
    end

    it "raises WebhookTimestampError when webhook-timestamp is missing" do
      expect do
        described_class.extract(headers: headers.except("webhook-timestamp"), body:, secret:)
      end.to raise_error(Dinie::WebhookTimestampError, /webhook-timestamp/)
    end

    it "raises WebhookSignatureError when webhook-signature is missing" do
      expect do
        described_class.extract(headers: headers.except("webhook-signature"), body:, secret:)
      end.to raise_error(Dinie::WebhookSignatureError, /webhook-signature/)
    end
  end

  describe "header lookup (deferred decision §21.5 — case-insensitive + symbol/string)" do
    it "finds headers regardless of capitalization" do
      capitalized = {
        "Webhook-Id" => webhook_id, "WEBHOOK-TIMESTAMP" => timestamp, "Webhook-Signature" => signature
      }

      expect(described_class.extract(headers: capitalized, body:, secret:)).to be_a(Dinie::Events::LoanActive)
    end

    it "finds headers given as symbol keys" do
      symbolic = { "webhook-id": webhook_id, "webhook-timestamp": timestamp, "webhook-signature": signature }

      expect(described_class.extract(headers: symbolic, body:, secret:)).to be_a(Dinie::Events::LoanActive)
    end

    it "takes the first value when a header arrives as a list" do
      listy = headers.merge("webhook-signature" => [signature, "v1,ignored"])

      expect(described_class.extract(headers: listy, body:, secret:)).to be_a(Dinie::Events::LoanActive)
    end
  end

  describe "unknown event type (verified but not in the catalog) → UnknownWebhookEventError" do
    it "raises with the unrecognized type preserved on .event_type" do
      unknown_body = JSON.generate(webhook_envelope(type: "loan.refinanced", data: { id: "ln_1" }))
      sig = sign_webhook(secret, webhook_id, timestamp, unknown_body)

      expect do
        described_class.extract(headers: headers.merge("webhook-signature" => sig), body: unknown_body, secret:)
      end.to raise_error(Dinie::UnknownWebhookEventError) { |error| expect(error.event_type).to eq("loan.refinanced") }
    end

    it "only reaches the unknown-type guard AFTER verifying the signature (no dispatch on bad sig)" do
      unknown_body = JSON.generate(webhook_envelope(type: "loan.refinanced", data: { id: "ln_1" }))

      # Signature was computed for the loan.active body, not this one → signature failure wins.
      expect { described_class.extract(headers:, body: unknown_body, secret:) }
        .to raise_error(Dinie::WebhookSignatureError)
    end
  end
end

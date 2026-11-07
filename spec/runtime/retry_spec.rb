# frozen_string_literal: true

require "faraday"

RSpec.describe Dinie::Internal::Retry do
  describe "RETRYABLE_STATUS" do
    it "is exactly {408, 429, 500, 502, 503, 504}" do
      expect(described_class::RETRYABLE_STATUS).to eq(Set[408, 429, 500, 502, 503, 504])
    end
  end

  describe ".should_retry?" do
    [408, 429, 500, 502, 503, 504].each do |status|
      it "retries #{status}" do
        expect(described_class.should_retry?(status)).to be(true)
      end
    end

    # 409 (semantic conflict) and 410 (gone) must NOT retry — the headline retry-matrix invariant.
    [400, 401, 403, 404, 409, 410, 422, 200, 201, 204].each do |status|
      it "does not retry #{status}" do
        expect(described_class.should_retry?(status)).to be(false)
      end
    end
  end

  describe ".idempotency_key_in_use?" do
    it "is true for a 409 whose code is idempotency_key_in_use" do
      expect(described_class.idempotency_key_in_use?(409, "idempotency_key_in_use")).to be(true)
    end

    it "is false for a 409 with any other code, or none" do
      expect(described_class.idempotency_key_in_use?(409, "email_already_exists")).to be(false)
      expect(described_class.idempotency_key_in_use?(409, nil)).to be(false)
    end

    it "is false for the same code on another status" do
      expect(described_class.idempotency_key_in_use?(422, "idempotency_key_in_use")).to be(false)
    end
  end

  describe ".retryable_network_error?" do
    it "retries a Faraday timeout" do
      expect(described_class.retryable_network_error?(Faraday::TimeoutError.new)).to be(true)
    end

    it "retries a Faraday connection failure" do
      expect(described_class.retryable_network_error?(Faraday::ConnectionFailed.new("reset"))).to be(true)
    end

    it "does not retry an arbitrary error" do
      expect(described_class.retryable_network_error?(RuntimeError.new)).to be(false)
    end

    it "does not retry a non-transport Faraday error (e.g. SSL)" do
      expect(described_class.retryable_network_error?(Faraday::SSLError.new("bad cert"))).to be(false)
    end
  end

  describe ".retry_delay" do
    context "Retry-After precedence (no jitter)" do
      it "honors Retry-After delta-seconds" do
        expect(described_class.retry_delay(0, retry_after: "5")).to eq(5.0)
      end

      it "prefers Retry-After-Ms over Retry-After" do
        expect(described_class.retry_delay(2, retry_after: "5", retry_after_ms: "1500")).to eq(1.5)
      end

      it "caps Retry-After at 60s" do
        expect(described_class.retry_delay(0, retry_after: "120")).to eq(60.0)
      end

      it "uses the first value of a repeated Retry-After header" do
        expect(described_class.retry_delay(0, retry_after: %w[7 99])).to eq(7.0)
      end
    end

    context "exponential backoff with subtractive jitter (band)" do
      # base = min(0.5 * 2^attempt, 8); delay ∈ (base*0.75, base]. Sample repeatedly: always in band.
      {
        0 => 0.5,
        1 => 1.0,
        2 => 2.0,
        3 => 4.0,
        4 => 8.0,
        5 => 8.0 # clamped at the ceiling
      }.each do |attempt, base|
        it "stays within [#{(base * 0.75).round(3)}, #{base}] for attempt #{attempt}" do
          50.times do
            delay = described_class.retry_delay(attempt)
            expect(delay).to be_between(base * 0.75, base)
          end
        end
      end
    end
  end
end

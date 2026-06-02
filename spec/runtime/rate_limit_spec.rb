# frozen_string_literal: true

RSpec.describe Dinie::RateLimit do
  subject(:rate_limit) { described_class.new(limit: 100, remaining: 87, reset_at: reset_at) }

  let(:reset_at) { Time.utc(2026, 6, 2, 12, 0, 30) }

  it "exposes limit, remaining, and reset_at" do
    expect(rate_limit.limit).to eq(100)
    expect(rate_limit.remaining).to eq(87)
    expect(rate_limit.reset_at).to eq(reset_at)
  end

  it "exposes reset_at as a Time (the SDK's only Time — RB6)" do
    expect(rate_limit.reset_at).to be_a(Time)
  end

  it "is frozen and value-equal" do
    expect(rate_limit).to be_frozen
    expect(rate_limit).to eq(described_class.new(limit: 100, remaining: 87, reset_at: reset_at))
    expect(rate_limit).not_to eq(described_class.new(limit: 100, remaining: 0, reset_at: reset_at))
  end

  it "supports pattern matching via deconstruct_keys" do
    matched =
      case rate_limit
      in { remaining: Integer => left }
        left
      end
    expect(matched).to eq(87)
  end

  it "exposes a deterministic to_h" do
    expect(rate_limit.to_h).to eq(limit: 100, remaining: 87, reset_at: reset_at)
  end
end

RSpec.describe Dinie::Internal::RateLimitTracker do
  subject(:tracker) { described_class.new }

  def headers(overrides = {})
    {
      "x-ratelimit-limit" => "100",
      "x-ratelimit-remaining" => "87",
      "x-ratelimit-reset" => "1800000000" # absolute epoch (≥ 1e9)
    }.merge(overrides)
  end

  describe ".parse" do
    it "parses the three X-RateLimit-* headers into a RateLimit" do
      parsed = described_class.parse(headers)
      expect(parsed).to eq(Dinie::RateLimit.new(limit: 100, remaining: 87, reset_at: Time.at(1_800_000_000)))
    end

    it "reads a reset value ≥ 1e9 as an absolute Unix epoch" do
      parsed = described_class.parse(headers("x-ratelimit-reset" => "1800000000"))
      expect(parsed.reset_at).to eq(Time.at(1_800_000_000))
    end

    it "reads a small reset value as a delta in seconds from now" do
      parsed = described_class.parse(headers("x-ratelimit-reset" => "30"))
      expect(parsed.reset_at).to be_within(2).of(Time.now + 30)
    end

    it "looks headers up case-insensitively and unwraps repeated values" do
      parsed = described_class.parse(
        "X-RateLimit-Limit" => %w[100 5], "X-RateLimit-Remaining" => "87", "X-RateLimit-Reset" => "1800000000"
      )
      expect(parsed.limit).to eq(100)
    end

    it "returns nil when any header is missing (all-or-nothing)" do
      expect(described_class.parse(headers.tap { |h| h.delete("x-ratelimit-remaining") })).to be_nil
    end

    it "returns nil on a garbage count" do
      expect(described_class.parse(headers("x-ratelimit-remaining" => "not-a-number"))).to be_nil
    end

    it "returns nil on a negative count" do
      expect(described_class.parse(headers("x-ratelimit-limit" => "-1"))).to be_nil
    end
  end

  describe "#snapshot / #update" do
    it "starts nil before any response" do
      expect(tracker.snapshot).to be_nil
    end

    it "captures the latest snapshot on update" do
      tracker.update(headers)
      expect(tracker.snapshot.remaining).to eq(87)
    end

    it "keeps the previous snapshot when a later response lacks valid headers" do
      tracker.update(headers)
      tracker.update("content-type" => "application/json") # header-less (e.g. token call)
      expect(tracker.snapshot.remaining).to eq(87)
    end
  end
end

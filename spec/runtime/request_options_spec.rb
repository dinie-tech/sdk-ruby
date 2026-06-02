# frozen_string_literal: true

RSpec.describe Dinie::Internal::RequestOptions do
  describe "defaults" do
    it "defaults every option to nil" do
      opts = described_class.new
      expect(opts.to_h).to eq(timeout: nil, idempotency_key: nil, headers: nil, max_retries: nil)
    end

    it "treats nil as an empty option set when coercing" do
      expect(described_class.coerce(nil).to_h)
        .to eq(timeout: nil, idempotency_key: nil, headers: nil, max_retries: nil)
    end
  end

  describe ".coerce" do
    it "passes an existing instance through unchanged" do
      opts = described_class.new(timeout: 5)
      expect(described_class.coerce(opts)).to equal(opts)
    end

    it "builds from a symbol-keyed hash" do
      expect(described_class.coerce(timeout: 5).timeout).to eq(5)
    end

    it "accepts string keys" do
      expect(described_class.coerce("timeout" => 5).timeout).to eq(5)
    end

    it "raises on an unknown key" do
      expect { described_class.coerce(bogus: 1) }.to raise_error(ArgumentError, /unknown keyword: :bogus/)
    end
  end

  describe "timeout" do
    it "accepts a non-negative Numeric (seconds)" do
      expect(described_class.new(timeout: 2.5).timeout).to eq(2.5)
      expect(described_class.new(timeout: 0).timeout).to eq(0)
    end

    it "rejects a non-Numeric value" do
      expect { described_class.new(timeout: "5") }.to raise_error(ArgumentError, /timeout/)
    end

    it "rejects a negative value" do
      expect { described_class.new(timeout: -1) }.to raise_error(ArgumentError, /timeout/)
    end
  end

  describe "idempotency_key" do
    it "accepts a String" do
      expect(described_class.new(idempotency_key: "key_1").idempotency_key).to eq("key_1")
    end

    it "rejects a non-String" do
      expect { described_class.new(idempotency_key: 123) }.to raise_error(ArgumentError, /idempotency_key/)
    end
  end

  describe "max_retries" do
    it "accepts a non-negative Integer" do
      expect(described_class.new(max_retries: 0).max_retries).to eq(0)
      expect(described_class.new(max_retries: 5).max_retries).to eq(5)
    end

    it "rejects a non-Integer" do
      expect { described_class.new(max_retries: 1.5) }.to raise_error(ArgumentError, /max_retries/)
    end

    it "rejects a negative value" do
      expect { described_class.new(max_retries: -1) }.to raise_error(ArgumentError, /max_retries/)
    end
  end

  describe "headers" do
    it "accepts a Hash and stringifies keys" do
      opts = described_class.new(headers: { authorization: "Bearer x" })
      expect(opts.headers).to eq("authorization" => "Bearer x")
    end

    it "preserves a nil value (the signal to remove a default)" do
      opts = described_class.new(headers: { "x-default" => nil })
      expect(opts.headers).to eq("x-default" => nil)
    end

    it "rejects a non-Hash value" do
      expect { described_class.new(headers: "nope") }.to raise_error(ArgumentError, /headers/)
    end

    it "rejects a non-String, non-nil header value" do
      expect { described_class.new(headers: { "x" => 1 }) }.to raise_error(ArgumentError, /headers/)
    end
  end

  describe "value semantics" do
    it "is frozen after construction" do
      expect(described_class.new(timeout: 5)).to be_frozen
    end

    it "compares by value" do
      expect(described_class.new(timeout: 5)).to eq(described_class.new(timeout: 5))
      expect(described_class.new(timeout: 5)).not_to eq(described_class.new(timeout: 6))
    end

    it "round-trips through to_h" do
      opts = described_class.new(timeout: 5, idempotency_key: "k", headers: { "a" => "b" }, max_retries: 2)
      expect(opts.to_h).to eq(timeout: 5, idempotency_key: "k", headers: { "a" => "b" }, max_retries: 2)
    end
  end
end

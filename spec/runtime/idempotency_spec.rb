# frozen_string_literal: true

RSpec.describe Dinie::Internal::Idempotency do
  describe "KEY_PREFIX" do
    it "marks SDK-generated keys with the dinie-sdk-retry- prefix" do
      expect(described_class::KEY_PREFIX).to eq("dinie-sdk-retry-")
    end
  end

  describe ".generate_key" do
    it "produces a prefixed UUID key" do
      key = described_class.generate_key
      expect(key).to start_with("dinie-sdk-retry-")
      expect(key.delete_prefix("dinie-sdk-retry-"))
        .to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
    end

    it "generates a fresh key on every call" do
      expect(described_class.generate_key).not_to eq(described_class.generate_key)
    end
  end
end

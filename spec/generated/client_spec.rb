# frozen_string_literal: true

RSpec.describe Dinie::Client do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_url) { "#{base_url}/auth/token" }

  # Isolate from the developer's real environment: every DINIE_* lookup defaults to absent unless a
  # test opts in. The client reads these via `ENV.fetch(key, nil)`.
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("DINIE_CLIENT_ID", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("DINIE_CLIENT_SECRET", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("DINIE_BASE_URL", nil).and_return(nil)
  end

  def build_client(**overrides)
    described_class.new(client_id: "id-1", client_secret: "secret-1", base_url: base_url, **overrides)
  end

  describe "credential resolution" do
    it "raises a clear error when no client id is resolvable" do
      expect { described_class.new(base_url: base_url) }
        .to raise_error(Dinie::Error, /client id/)
    end

    it "raises a clear error when no client secret is resolvable" do
      expect { described_class.new(client_id: "id-1", base_url: base_url) }
        .to raise_error(Dinie::Error, /client secret/)
    end

    it "falls back to DINIE_CLIENT_ID / DINIE_CLIENT_SECRET env vars" do
      allow(ENV).to receive(:fetch).with("DINIE_CLIENT_ID", nil).and_return("env-id")
      allow(ENV).to receive(:fetch).with("DINIE_CLIENT_SECRET", nil).and_return("env-secret")
      expect { described_class.new(base_url: base_url) }.not_to raise_error
    end
  end

  describe "transport + auth wiring" do
    it "exposes a nil rate-limit snapshot before any request" do
      expect(build_client.rate_limit).to be_nil
    end

    it "injects ONE shared connection into both the HttpClient and the TokenManager (pool-sharing)" do
      client = build_client
      http = client.instance_variable_get(:@http)
      token_manager = client.instance_variable_get(:@token_manager)
      shared = client.instance_variable_get(:@connection)

      expect(http.instance_variable_get(:@connection)).to be(shared)
      expect(token_manager.instance_variable_get(:@connection)).to be(shared)
    end
  end

  describe "#with_options" do
    it "returns a distinct client sharing the SAME TokenManager and connection" do
      client = build_client
      clone = client.with_options(timeout: 5)

      expect(clone).to be_a(described_class)
      expect(clone).not_to be(client)
      expect(clone.instance_variable_get(:@token_manager)).to be(client.instance_variable_get(:@token_manager))
      expect(clone.instance_variable_get(:@connection)).to be(client.instance_variable_get(:@connection))
    end

    it "merges config onto the clone while leaving the original untouched" do
      client = build_client(timeout: 30)
      clone = client.with_options(timeout: 5)

      expect(clone.instance_variable_get(:@http).instance_variable_get(:@timeout)).to eq(5)
      expect(client.instance_variable_get(:@http).instance_variable_get(:@timeout)).to eq(30)
    end

    it "reuses the cached token on the clone — a per-call override never re-authenticates" do
      stub_request(:post, token_url)
        .to_return(status: 200, body: JSON.generate(access_token: "tok-1", token_type: "bearer", expires_in: 3_600))
      stub_request(:get, "#{base_url}/ping").to_return(status: 200, body: "{}")

      client = build_client
      # Drive a request through the original (acquires the token: ONE /auth/token POST)…
      client.instance_variable_get(:@http).request(method: :get, path: "/ping")
      # …then through a per-call-config clone, which shares the token cache (no second POST).
      clone = client.with_options(timeout: 5)
      clone.instance_variable_get(:@http).request(method: :get, path: "/ping")

      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:get, "#{base_url}/ping")).to have_been_made.twice
    end
  end
end

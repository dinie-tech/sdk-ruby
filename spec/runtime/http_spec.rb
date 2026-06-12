# frozen_string_literal: true

require "faraday"
require_relative "../support/fake_token_manager"

RSpec.describe Dinie::Internal::HttpClient do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_manager) { FakeTokenManager.new(tokens: %w[token-1 token-2]) }
  let(:slept) { [] }
  let(:sleeper) { ->(seconds) { slept << seconds } }

  def build_client(**overrides)
    described_class.new(token_manager: token_manager, base_url: base_url, sleeper: sleeper, **overrides)
  end

  def url(path)
    "#{base_url}#{path}"
  end

  describe "transport + success" do
    it "returns a JSON body parsed with symbol keys (resources deserialize it)" do
      stub_request(:get, url("/customers"))
        .to_return(status: 200, body: '{"object":"list","data":[{"id":"cust_1"}],"has_more":false}')
      result = build_client.request(method: :get, path: "/customers")
      expect(result).to eq(object: "list", data: [{ id: "cust_1" }], has_more: false)
    end

    it "returns nil for a 204 (no content)" do
      stub_request(:delete, url("/webhook_endpoints/we_1")).to_return(status: 204)
      expect(build_client.request(method: :delete, path: "/webhook_endpoints/we_1")).to be_nil
    end

    it "returns nil for an empty 200 body" do
      stub_request(:get, url("/empty")).to_return(status: 200, body: "")
      expect(build_client.request(method: :get, path: "/empty")).to be_nil
    end

    it "returns raw text for a non-JSON success body" do
      stub_request(:get, url("/text")).to_return(status: 200, body: "plain text")
      expect(build_client.request(method: :get, path: "/text")).to eq("plain text")
    end

    it "resolves base_url + bare path to the /api/v3 prefix (no leading-slash collision)" do
      stub_request(:get, url("/customers")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/customers")
      expect(a_request(:get, "https://api.dinie.test/api/v3/customers")).to have_been_made
    end

    it "appends query params and drops nil values" do
      stub_request(:get, url("/customers")).with(query: { limit: "50" }).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/customers", query: { limit: 50, starting_after: nil })
      expect(a_request(:get, url("/customers")).with(query: { limit: "50" })).to have_been_made
    end
  end

  describe "telemetry headers" do
    it "sends the User-Agent and X-Dinie-SDK-* headers with the Bearer token" do
      stub_request(:get, url("/x")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/x")
      version = Dinie::VERSION
      api_ver = Dinie::Generated::API_VERSION
      user_agent = %r{\ADinie-SDK-Ruby/#{Regexp.escape(version)} \(api-version=#{Regexp.escape(api_ver)}; ruby/#{Regexp.escape(RUBY_VERSION)}\)\z}
      expect(
        a_request(:get, url("/x")).with(headers: {
                                          "User-Agent" => user_agent,
                                          "Accept" => "application/json",
                                          "Authorization" => "Bearer token-1",
                                          "X-Dinie-Sdk-Language" => "ruby",
                                          "X-Dinie-Sdk-Version" => version,
                                          "X-Dinie-Sdk-Runtime" => "ruby/#{RUBY_VERSION}"
                                        })
      ).to have_been_made
    end

    it "adds X-Dinie-Retry-Count on a retried attempt" do
      stub_request(:get, url("/r")).to_return({ status: 500, body: "{}" }, { status: 200, body: "{}" })
      build_client.request(method: :get, path: "/r")
      expect(a_request(:get, url("/r")).with(headers: { "X-Dinie-Retry-Count" => "1" })).to have_been_made
    end
  end

  describe "retry matrix (status)" do
    [408, 429, 500, 502, 503, 504].each do |status|
      it "retries #{status} then succeeds" do
        stub_request(:get, url("/m")).to_return({ status: status, body: "{}" }, { status: 200, body: '{"ok":true}' })
        result = build_client.request(method: :get, path: "/m")
        expect(result).to eq(ok: true)
        expect(a_request(:get, url("/m"))).to have_been_made.times(2)
        expect(slept.size).to eq(1)
      end
    end

    it "does NOT retry 409 (semantic conflict) → ConflictError, one request" do
      stub_request(:post, url("/c"))
        .to_return(status: 409, body: '{"type":"https://docs.dinie.com/errors/conflict"}')
      expect { build_client.request(method: :post, path: "/c", body: { a: 1 }) }.to raise_error(Dinie::ConflictError)
      expect(a_request(:post, url("/c"))).to have_been_made.times(1)
      expect(slept).to be_empty
    end

    it "does NOT retry 410 (gone) → generic APIStatusError, one request" do
      stub_request(:get, url("/g")).to_return(status: 410, body: "{}")
      expect { build_client.request(method: :get, path: "/g") }
        .to raise_error(Dinie::APIStatusError) { |e| expect(e).to be_instance_of(Dinie::APIStatusError) }
      expect(a_request(:get, url("/g"))).to have_been_made.times(1)
      expect(slept).to be_empty
    end
  end

  describe "retry budget" do
    it "exhausts the default budget (1 + 3) then raises the typed error" do
      stub_request(:get, url("/e")).to_return(status: 500, body: "{}")
      expect { build_client.request(method: :get, path: "/e") }.to raise_error(Dinie::ServerError)
      expect(a_request(:get, url("/e"))).to have_been_made.times(4)
      expect(slept.size).to eq(3)
    end

    it "honors a per-call max_retries override" do
      stub_request(:get, url("/e1")).to_return(status: 503, body: "{}")
      expect do
        build_client.request(method: :get, path: "/e1", request_options: { max_retries: 1 })
      end.to raise_error(Dinie::ServerError)
      expect(a_request(:get, url("/e1"))).to have_been_made.times(2)
      expect(slept.size).to eq(1)
    end

    it "honors a client-level max_retries of 0 (no retries)" do
      stub_request(:get, url("/e0")).to_return(status: 500, body: "{}")
      expect { build_client(max_retries: 0).request(method: :get, path: "/e0") }.to raise_error(Dinie::ServerError)
      expect(a_request(:get, url("/e0"))).to have_been_made.times(1)
      expect(slept).to be_empty
    end
  end

  describe "backoff + jitter (band)" do
    it "sleeps min(0.5·2^attempt, 8)s minus ≤25% jitter on each retry" do
      stub_request(:get, url("/b")).to_return(status: 500, body: "{}")
      expect { build_client.request(method: :get, path: "/b") }.to raise_error(Dinie::ServerError)
      expect(slept.size).to eq(3)
      expect(slept[0]).to be_between(0.375, 0.5)
      expect(slept[1]).to be_between(0.75, 1.0)
      expect(slept[2]).to be_between(1.5, 2.0)
    end
  end

  describe "Retry-After precedence (cap 60s)" do
    it "uses Retry-After (delta-seconds) over the computed backoff" do
      stub_request(:get, url("/ra"))
        .to_return({ status: 429, headers: { "Retry-After" => "5" }, body: "{}" }, { status: 200, body: "{}" })
      build_client.request(method: :get, path: "/ra")
      expect(slept).to eq([5.0])
    end

    it "caps Retry-After at 60s" do
      stub_request(:get, url("/ra2"))
        .to_return({ status: 503, headers: { "Retry-After" => "120" }, body: "{}" }, { status: 200, body: "{}" })
      build_client.request(method: :get, path: "/ra2")
      expect(slept).to eq([60.0])
    end

    it "prefers Retry-After-Ms (milliseconds)" do
      stub_request(:get, url("/ra3"))
        .to_return({ status: 429, headers: { "Retry-After-Ms" => "1500" }, body: "{}" }, { status: 200, body: "{}" })
      build_client.request(method: :get, path: "/ra3")
      expect(slept).to eq([1.5])
    end
  end

  describe "idempotency" do
    it "auto-generates an X-Idempotency-Key on POST" do
      stub_request(:post, url("/i")).to_return(status: 201, body: "{}")
      build_client.request(method: :post, path: "/i", body: { a: 1 })
      expect(
        a_request(:post, url("/i")).with { |req| req.headers["X-Idempotency-Key"]&.start_with?("dinie-sdk-retry-") }
      ).to have_been_made
    end

    it "auto-generates an X-Idempotency-Key on PATCH" do
      stub_request(:patch, url("/ip")).to_return(status: 200, body: "{}")
      build_client.request(method: :patch, path: "/ip", body: { a: 1 })
      expect(
        a_request(:patch, url("/ip")).with { |req| req.headers.key?("X-Idempotency-Key") }
      ).to have_been_made
    end

    it "sends no X-Idempotency-Key on GET" do
      stub_request(:get, url("/ig")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/ig")
      expect(a_request(:get, url("/ig")).with { |req| !req.headers.key?("X-Idempotency-Key") }).to have_been_made
    end

    it "reuses the SAME key across every retry (generated once, before the loop)" do
      keys = []
      stub_request(:post, url("/once")).to_return do |request|
        keys << request.headers["X-Idempotency-Key"]
        { status: keys.size < 3 ? 500 : 201, body: "{}" }
      end
      build_client.request(method: :post, path: "/once", body: { a: 1 })
      expect(keys.size).to eq(3)
      expect(keys.uniq.size).to eq(1)
    end

    it "opts out globally with idempotency: false" do
      stub_request(:post, url("/io")).to_return(status: 201, body: "{}")
      build_client(idempotency: false).request(method: :post, path: "/io", body: { a: 1 })
      expect(a_request(:post, url("/io")).with { |req| !req.headers.key?("X-Idempotency-Key") }).to have_been_made
    end

    it "honors a per-call idempotency_key override" do
      stub_request(:post, url("/ik")).to_return(status: 201, body: "{}")
      build_client.request(method: :post, path: "/ik", body: { a: 1 }, request_options: { idempotency_key: "key-123" })
      expect(a_request(:post, url("/ik")).with(headers: { "X-Idempotency-Key" => "key-123" })).to have_been_made
    end

    it "honors a per-call key even when idempotency is globally opted out" do
      stub_request(:post, url("/iko")).to_return(status: 201, body: "{}")
      build_client(idempotency: false)
        .request(method: :post, path: "/iko", body: { a: 1 }, request_options: { idempotency_key: "explicit" })
      expect(a_request(:post, url("/iko")).with(headers: { "X-Idempotency-Key" => "explicit" })).to have_been_made
    end
  end

  describe "401 one-shot re-auth" do
    it "invalidates the token, retries once with a fresh token, then succeeds" do
      auths = []
      stub_request(:get, url("/auth")).to_return do |request|
        auths << request.headers["Authorization"]
        { status: auths.size == 1 ? 401 : 200, body: "{}" }
      end
      result = build_client.request(method: :get, path: "/auth")
      expect(result).to eq({})
      expect(token_manager.invalidate_count).to eq(1)
      expect(auths).to eq(["Bearer token-1", "Bearer token-2"])
      expect(a_request(:get, url("/auth"))).to have_been_made.times(2)
      expect(slept).to be_empty
    end

    it "carries X-Dinie-Retry-Count on the re-authed attempt" do
      stub_request(:get, url("/authc")).to_return({ status: 401, body: "{}" }, { status: 200, body: "{}" })
      build_client.request(method: :get, path: "/authc")
      expect(a_request(:get, url("/authc")).with(headers: { "X-Dinie-Retry-Count" => "1" })).to have_been_made
    end

    it "gives up with AuthError on a persistent 401 (no loop)" do
      stub_request(:get, url("/auth2")).to_return(status: 401, body: "{}")
      expect { build_client.request(method: :get, path: "/auth2") }.to raise_error(Dinie::AuthError)
      expect(token_manager.invalidate_count).to eq(1)
      expect(a_request(:get, url("/auth2"))).to have_been_made.times(2)
    end

    it "forces AuthError even if the persistent 401 body carries a different type URL" do
      stub_request(:get, url("/auth3"))
        .to_return(status: 401, body: '{"type":"https://docs.dinie.com/errors/validation-failed"}')
      expect { build_client.request(method: :get, path: "/auth3") }.to raise_error(Dinie::AuthError)
    end
  end

  describe "network errors" do
    it "retries a timeout and raises APITimeoutError once the budget is exhausted" do
      stub_request(:get, url("/to")).to_timeout
      expect { build_client.request(method: :get, path: "/to") }.to raise_error(Dinie::APITimeoutError)
      expect(a_request(:get, url("/to"))).to have_been_made.times(4)
      expect(slept.size).to eq(3)
    end

    it "recovers when a timeout is followed by success" do
      stub_request(:get, url("/to2")).to_timeout.then.to_return(status: 200, body: "{}")
      expect(build_client.request(method: :get, path: "/to2")).to eq({})
      expect(slept.size).to eq(1)
    end

    it "raises APIConnectionError on a persistent connection failure" do
      stub_request(:get, url("/cf")).to_raise(Errno::ECONNRESET)
      expect { build_client.request(method: :get, path: "/cf") }
        .to raise_error(Dinie::APIConnectionError) { |e| expect(e).to be_instance_of(Dinie::APIConnectionError) }
    end
  end

  describe "per-call timeout wiring" do
    let(:captured) { [] }
    let(:test_connection) do
      Faraday.new do |faraday|
        faraday.adapter :test do |stub|
          stub.get(url("/t")) do |env|
            captured << env.request.timeout
            [200, {}, "{}"]
          end
        end
      end
    end

    def client_with_test_connection
      described_class.new(token_manager: token_manager, base_url: base_url, connection: test_connection)
    end

    it "applies the default timeout of 30s" do
      client_with_test_connection.request(method: :get, path: "/t")
      expect(captured.last).to eq(30)
    end

    it "applies a per-call timeout override (in seconds — RB17)" do
      client_with_test_connection.request(method: :get, path: "/t", request_options: { timeout: 7 })
      expect(captured.last).to eq(7)
    end
  end

  describe "rate-limit snapshot" do
    def rate_limit_headers
      { "X-RateLimit-Limit" => "100", "X-RateLimit-Remaining" => "87", "X-RateLimit-Reset" => "1800000000" }
    end

    it "is nil before any request" do
      expect(build_client.rate_limit).to be_nil
    end

    it "captures X-RateLimit-* from the latest response" do
      stub_request(:get, url("/rl")).to_return(status: 200, body: "{}", headers: rate_limit_headers)
      client = build_client
      client.request(method: :get, path: "/rl")
      snapshot = client.rate_limit
      expect(snapshot).to be_a(Dinie::RateLimit)
      expect(snapshot.limit).to eq(100)
      expect(snapshot.remaining).to eq(87)
      expect(snapshot.reset_at).to be_a(Time)
    end

    it "keeps the previous snapshot when a later response lacks the headers" do
      stub_request(:get, url("/rl2"))
        .to_return({ status: 200, body: "{}", headers: rate_limit_headers }, { status: 200, body: "{}" })
      client = build_client
      client.request(method: :get, path: "/rl2")
      client.request(method: :get, path: "/rl2")
      expect(client.rate_limit.remaining).to eq(87)
    end
  end

  describe "error dispatch (via from_response)" do
    it "routes a 422 with a type URL to ValidationError and surfaces its fields" do
      stub_request(:post, url("/d"))
        .to_return(status: 422, headers: { "X-Request-Id" => "req_42" },
                   body: '{"type":"https://docs.dinie.com/errors/validation-failed","detail":"cpf is invalid"}')
      build_client.request(method: :post, path: "/d", body: { a: 1 })
    rescue Dinie::ValidationError => e
      expect(e.status).to eq(422)
      expect(e.detail).to eq("cpf is invalid")
      expect(e.request_id).to eq("req_42")
    else
      raise "expected a ValidationError"
    end

    it "routes a 400 to BadRequestError" do
      stub_request(:get, url("/d4"))
        .to_return(status: 400, body: '{"type":"https://docs.dinie.com/errors/invalid-request"}')
      expect { build_client.request(method: :get, path: "/d4") }.to raise_error(Dinie::BadRequestError)
    end

    it "routes a 404 to NotFoundError" do
      stub_request(:get, url("/d404")).to_return(status: 404, body: "{}")
      expect { build_client.request(method: :get, path: "/d404") }.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "per-call header overrides" do
    it "adds an extra header" do
      stub_request(:get, url("/h")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/h", request_options: { headers: { "X-Trace" => "abc" } })
      expect(a_request(:get, url("/h")).with(headers: { "X-Trace" => "abc" })).to have_been_made
    end

    it "overrides a default header value" do
      stub_request(:get, url("/h1")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/h1", request_options: { headers: { "accept" => "text/plain" } })
      expect(a_request(:get, url("/h1")).with(headers: { "Accept" => "text/plain" })).to have_been_made
    end

    it "removes a default header when the override value is nil" do
      stub_request(:get, url("/h2")).to_return(status: 200, body: "{}")
      build_client.request(method: :get, path: "/h2", request_options: { headers: { "x-dinie-sdk-language" => nil } })
      expect(
        a_request(:get, url("/h2")).with { |req| !req.headers.key?("X-Dinie-Sdk-Language") }
      ).to have_been_made
    end
  end
end

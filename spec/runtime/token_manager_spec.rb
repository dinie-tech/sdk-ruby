# frozen_string_literal: true

require "base64"

RSpec.describe Dinie::Internal::TokenManager do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:client_id) { "client-abc" }
  let(:client_secret) { "secret-xyz" }
  let(:token_url) { "#{base_url}/auth/token" }
  # A controllable "seconds now" clock so the refresh-margin boundary is exercised deterministically
  # (no wall-clock dependence). Mutate `now[0]` to advance time.
  let(:now) { [1_000.0] }
  let(:clock) { -> { now[0] } }

  def build_manager(**overrides)
    described_class.new(client_id: client_id, client_secret: client_secret, base_url: base_url,
                        clock: clock, **overrides)
  end

  def token_body(access_token: "tok-1", expires_in: 3_600, token_type: "bearer")
    JSON.generate(access_token: access_token, token_type: token_type, expires_in: expires_in)
  end

  def stub_token(**body_overrides)
    stub_request(:post, token_url).to_return(status: 200, body: token_body(**body_overrides))
  end

  describe "refresh request shape (RFC 6749 client_credentials)" do
    it "POSTs Basic auth + form-encoded grant and returns the access_token" do
      stub_token(access_token: "tok-shape")
      expect(build_manager.access_token).to eq("tok-shape")

      basic = Base64.strict_encode64("#{client_id}:#{client_secret}")
      expect(
        a_request(:post, token_url).with(
          body: "grant_type=client_credentials",
          headers: {
            "Authorization" => "Basic #{basic}",
            "Content-Type" => "application/x-www-form-urlencoded"
          }
        )
      ).to have_been_made.once
    end

    it "appends /auth/token to the base URL (preserving the /api/v3 prefix)" do
      stub_token
      build_manager.access_token
      expect(a_request(:post, "https://api.dinie.test/api/v3/auth/token")).to have_been_made
    end
  end

  describe "cache + fast path" do
    it "returns the cached token without a second request inside the validity window" do
      stub_token(access_token: "tok-cached", expires_in: 3_600)
      manager = build_manager
      expect(manager.access_token).to eq("tok-cached")
      expect(manager.access_token).to eq("tok-cached")
      expect(a_request(:post, token_url)).to have_been_made.once
    end
  end

  describe "proactive refresh margin (300s boundary)" do
    it "does NOT refresh while still outside the margin (expiry − 301s)" do
      stub_token(expires_in: 3_600) # acquired at now=1000 ⇒ expires_at=4600, refresh at ≥ 4300
      manager = build_manager
      manager.access_token
      now[0] = 4_299 # 301s before expiry — still fresh
      manager.access_token
      expect(a_request(:post, token_url)).to have_been_made.once
    end

    it "refreshes once the margin is crossed (expiry − 300s)" do
      stub_request(:post, token_url).to_return(
        { status: 200, body: token_body(access_token: "tok-1", expires_in: 3_600) },
        { status: 200, body: token_body(access_token: "tok-2", expires_in: 3_600) }
      )
      manager = build_manager
      expect(manager.access_token).to eq("tok-1")
      now[0] = 4_300 # exactly 300s before expiry — inside the margin
      expect(manager.access_token).to eq("tok-2")
      expect(a_request(:post, token_url)).to have_been_made.twice
    end
  end

  describe "#invalidate! (the 401 one-shot seam)" do
    it "drops the cache so the next #access_token re-authenticates" do
      stub_request(:post, token_url).to_return(
        { status: 200, body: token_body(access_token: "tok-1") },
        { status: 200, body: token_body(access_token: "tok-2") }
      )
      manager = build_manager
      expect(manager.access_token).to eq("tok-1")
      manager.invalidate!
      expect(manager.access_token).to eq("tok-2")
      expect(a_request(:post, token_url)).to have_been_made.twice
    end
  end

  describe "thread-safety — double-check serialized refresh" do
    # Releases `count` threads as simultaneously as possible, then collects their return values
    # (Thread#value re-raises any error). The `until go` guard makes the latch immune to a
    # broadcast that races a thread not yet parked — no arbitrary sleep needed.
    def run_concurrently(count, &block) # rubocop:disable Metrics/MethodLength
      mutex = Mutex.new
      cond = ConditionVariable.new
      go = false
      threads = Array.new(count) do
        Thread.new do
          mutex.synchronize { cond.wait(mutex) until go }
          block.call
        end
      end
      mutex.synchronize do
        go = true
        cond.broadcast
      end
      threads.map(&:value)
    end

    it "issues exactly ONE token POST under N concurrent callers, all getting the same token" do
      # The token endpoint blocks until released, widening the contention window: every losing
      # caller is guaranteed to be parked on the condition variable while the single winner POSTs.
      gate = Queue.new
      stub_request(:post, token_url).to_return do |_request|
        gate.pop
        { status: 200, body: token_body(access_token: "tok-shared") }
      end

      manager = build_manager
      caller_count = 25
      results_thread = Thread.new { run_concurrently(caller_count) { manager.access_token } }
      gate.push(:release) # let the single in-flight refresh complete
      results = results_thread.value

      expect(results).to all(eq("tok-shared"))
      expect(results.size).to eq(caller_count)
      expect(a_request(:post, token_url)).to have_been_made.once
    end

    it "lets a later caller retry after a failed refresh (no permanently-stuck lock)" do
      stub_request(:post, token_url).to_return(
        { status: 500, body: "boom" },
        { status: 200, body: token_body(access_token: "tok-recovered") }
      )
      manager = build_manager
      expect { manager.access_token }.to raise_error(Dinie::OAuthError)
      expect(manager.access_token).to eq("tok-recovered")
      expect(a_request(:post, token_url)).to have_been_made.twice
    end
  end

  describe "handshake failures → OAuthError" do
    it "raises on a non-2xx token response (and includes status + detail)" do
      stub_request(:post, token_url).to_return(status: 401, body: "invalid_client")
      expect { build_manager.access_token }
        .to raise_error(Dinie::OAuthError, /status 401.*invalid_client/m)
    end

    it "raises on a transport failure before any response" do
      stub_request(:post, token_url).to_timeout
      expect { build_manager.access_token }.to raise_error(Dinie::OAuthError, /before a response/)
    end

    it "raises when the body is not valid JSON" do
      stub_request(:post, token_url).to_return(status: 200, body: "<html>nope</html>")
      expect { build_manager.access_token }.to raise_error(Dinie::OAuthError, /not valid JSON/)
    end

    it "raises when the JSON body is not an object" do
      stub_request(:post, token_url).to_return(status: 200, body: "[]")
      expect { build_manager.access_token }.to raise_error(Dinie::OAuthError, /not a JSON object/)
    end

    it "raises when access_token is missing" do
      stub_request(:post, token_url).to_return(status: 200, body: JSON.generate(expires_in: 3_600))
      expect { build_manager.access_token }.to raise_error(Dinie::OAuthError, /access_token/)
    end

    it "raises when expires_in is missing or non-positive" do
      stub_request(:post, token_url)
        .to_return(status: 200, body: JSON.generate(access_token: "tok", expires_in: 0))
      expect { build_manager.access_token }.to raise_error(Dinie::OAuthError, /expires_in/)
    end
  end
end

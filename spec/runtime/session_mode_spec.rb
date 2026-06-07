# frozen_string_literal: true

require "base64"

# Session-mode specs for {Dinie::Internal::TokenManager} — peer-port of the Python 015a suite.
#
# Session mode is activated by passing `code:` to the constructor. The manager performs a
# two-step exchange exactly once:
#   1. POST /auth/token (client_credentials) → cc-bearer
#   2. POST /biometrics/session-exchange (Bearer cc-bearer + { code }) → customer token
#
# After the session token expires (TTL or invalidate!), subsequent calls raise
# {Dinie::SessionTokenExpiredError}. The code is single-use — no re-exchange.
#
# T1  — two-step count + request shape
# T2  — customer bearer returned (and cached)
# T3  — partner mode regression (no code → no exchange)
# T4  — lazy constructor (no I/O)
# T5  — session token expiry → SessionTokenExpiredError
# T6  — single-flight: N concurrent callers → 1 exchange, all get customer token
# T9  — bad code → typed API error (AuthError / PermissionDeniedError), @exchanged stays false
RSpec.describe Dinie::Internal::TokenManager, "session mode" do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:client_id) { "client-abc" }
  let(:client_secret) { "secret-xyz" }
  let(:code) { "auth-code-123" }
  let(:token_url) { "#{base_url}/auth/token" }
  let(:exchange_url) { "#{base_url}#{described_class::SESSION_EXCHANGE_PATH}" }
  let(:now) { [1_000.0] }
  let(:clock) { -> { now[0] } }

  def build_session_manager(**overrides)
    described_class.new(
      client_id: client_id, client_secret: client_secret,
      base_url: base_url, clock: clock, code: code, **overrides
    )
  end

  def build_partner_manager(**overrides)
    described_class.new(
      client_id: client_id, client_secret: client_secret,
      base_url: base_url, clock: clock, **overrides
    )
  end

  def cc_body(access_token: "cc-tok-1", expires_in: 3_600)
    JSON.generate(access_token: access_token, token_type: "bearer", expires_in: expires_in)
  end

  def exchange_body(access_token: "customer-tok-1", expires_in: 3_600)
    JSON.generate(access_token: access_token, token_type: "bearer", expires_in: expires_in,
                  customer_id: "cust-42")
  end

  def stub_cc(**overrides)
    stub_request(:post, token_url).to_return(status: 200, body: cc_body(**overrides))
  end

  def stub_exchange(**overrides)
    stub_request(:post, exchange_url).to_return(status: 200, body: exchange_body(**overrides))
  end

  # ── T1: Two-step acquisition ───────────────────────────────────────────────────────────────

  describe "T1 — two-step acquisition (request count + shape)" do
    it "issues exactly 1 cc POST and 1 exchange POST on the first access_token" do
      stub_cc(access_token: "cc-tok-shape")
      stub_exchange(access_token: "cust-tok-shape")

      build_session_manager.access_token

      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end

    it "sends the cc-bearer in Authorization: Bearer on the exchange POST" do
      stub_cc(access_token: "cc-tok-bearer")
      stub_exchange

      build_session_manager.access_token

      expect(
        a_request(:post, exchange_url).with(
          headers: { "Authorization" => "Bearer cc-tok-bearer" }
        )
      ).to have_been_made.once
    end

    it "sends { code } JSON body on the exchange POST" do
      stub_cc
      stub_exchange

      build_session_manager.access_token

      expect(
        a_request(:post, exchange_url).with(body: JSON.generate(code: code))
      ).to have_been_made.once
    end

    it "hits SESSION_EXCHANGE_PATH for the exchange POST" do
      stub_cc
      stub_exchange

      build_session_manager.access_token

      expect(a_request(:post, exchange_url)).to have_been_made
    end

    it "does NOT send Basic auth on the exchange POST" do
      stub_cc(access_token: "cc-tok-check")
      stub_exchange

      build_session_manager.access_token

      basic = Base64.strict_encode64("#{client_id}:#{client_secret}")
      expect(
        a_request(:post, exchange_url).with(
          headers: { "Authorization" => "Basic #{basic}" }
        )
      ).not_to have_been_made
    end
  end

  # ── T2: Customer bearer returned (and cached) ──────────────────────────────────────────────

  describe "T2 — customer bearer returned and cached" do
    it "returns the customer token (not the cc-token)" do
      stub_cc(access_token: "cc-tok")
      stub_exchange(access_token: "cust-tok")

      expect(build_session_manager.access_token).to eq("cust-tok")
    end

    it "caches the customer token — second call makes no new requests" do
      stub_cc
      stub_exchange(access_token: "cust-tok-cached")

      manager = build_session_manager
      expect(manager.access_token).to eq("cust-tok-cached")
      expect(manager.access_token).to eq("cust-tok-cached")

      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end
  end

  # ── T3: Partner mode regression ───────────────────────────────────────────────────────────

  describe "T3 — partner mode regression (no code)" do
    it "makes exactly 1 cc POST and no exchange POST in partner mode" do
      stub_request(:post, token_url).to_return(status: 200, body: cc_body(access_token: "partner-tok"))

      expect(build_partner_manager.access_token).to eq("partner-tok")

      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).not_to have_been_made
    end

    it "partner mode refreshes on TTL expiry (REFRESH_MARGIN_SECONDS)" do
      stub_request(:post, token_url).to_return(
        { status: 200, body: cc_body(access_token: "partner-1", expires_in: 3_600) },
        { status: 200, body: cc_body(access_token: "partner-2", expires_in: 3_600) }
      )

      manager = build_partner_manager
      expect(manager.access_token).to eq("partner-1")
      now[0] = 4_300 # exactly at the REFRESH_MARGIN_SECONDS boundary (expires_at=4600, margin=300)
      expect(manager.access_token).to eq("partner-2")
      expect(a_request(:post, token_url)).to have_been_made.twice
    end
  end

  # ── T4: Lazy constructor ───────────────────────────────────────────────────────────────────

  describe "T4 — lazy constructor (no I/O)" do
    it "makes no network requests when the manager is constructed" do
      # No stubs registered — WebMock raises on any real connection attempt.
      # Simply building the manager must not raise.
      expect { build_session_manager }.not_to raise_error
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  # ── T5: Session token expiry → SessionTokenExpiredError ───────────────────────────────────

  describe "T5 — session token expiry → SessionTokenExpiredError" do
    it "raises SessionTokenExpiredError after invalidate! (no second exchange attempt)" do
      stub_cc
      stub_exchange(access_token: "cust-tok")

      manager = build_session_manager
      expect(manager.access_token).to eq("cust-tok")

      manager.invalidate!

      expect { manager.access_token }.to raise_error(Dinie::SessionTokenExpiredError)
      # Only the original 1 cc + 1 exchange — no third request after invalidate!
      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end

    it "raises SessionTokenExpiredError on natural TTL expiry (no cc-bearer re-attempt)" do
      stub_cc
      stub_exchange(access_token: "cust-tok-ttl", expires_in: 3_600)

      manager = build_session_manager
      expect(manager.access_token).to eq("cust-tok-ttl")

      # advance past expires_at=1000+3600=4600; with REFRESH_MARGIN_SECONDS=300, stale at 4300
      now[0] = 5_000

      expect { manager.access_token }.to raise_error(Dinie::SessionTokenExpiredError)
      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end

    it "raises SessionTokenExpiredError (not OAuthError, not APIStatusError) after invalidate!" do
      stub_cc
      stub_exchange(access_token: "cust-tok")

      manager = build_session_manager
      manager.access_token
      manager.invalidate!

      # SessionTokenExpiredError < Error (not < OAuthError, not < APIStatusError)
      expect { manager.access_token }.to raise_error(Dinie::SessionTokenExpiredError)
    end

    it "does not include the cc-bearer in the expiry error path" do
      stub_cc
      stub_exchange(access_token: "cust-tok")

      manager = build_session_manager
      manager.access_token
      manager.invalidate!

      begin
        manager.access_token
      rescue Dinie::SessionTokenExpiredError
        nil # expected
      end

      # No new request to token_url after the first exchange
      expect(a_request(:post, token_url)).to have_been_made.once
    end
  end

  # ── T6: Single-flight (N concurrent callers → 1 exchange) ─────────────────────────────────

  describe "T6 — single-flight: N concurrent callers → 1 exchange, all get customer token" do
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

    it "issues exactly ONE cc POST and ONE exchange POST under N concurrent callers" do
      gate = Queue.new
      stub_request(:post, token_url).to_return(status: 200, body: cc_body(access_token: "cc-shared"))
      stub_request(:post, exchange_url).to_return do |_req|
        gate.pop
        { status: 200, body: exchange_body(access_token: "cust-shared") }
      end

      manager = build_session_manager
      caller_count = 25
      results_thread = Thread.new { run_concurrently(caller_count) { manager.access_token } }
      gate.push(:release)
      results = results_thread.value

      expect(results).to all(eq("cust-shared"))
      expect(results.size).to eq(caller_count)
      expect(a_request(:post, token_url)).to have_been_made.once
      expect(a_request(:post, exchange_url)).to have_been_made.once
    end
  end

  # ── T9: Bad code → typed API error ────────────────────────────────────────────────────────

  describe "T9 — bad code → typed API error from from_response" do
    it "raises AuthError (not SessionTokenExpiredError) when exchange returns 401" do
      stub_cc(access_token: "cc-tok")
      stub_request(:post, exchange_url).to_return(
        status: 401, body: JSON.generate(type: "https://docs.dinie.com/errors/authentication-failed",
                                         detail: "invalid code")
      )

      expect { build_session_manager.access_token }.to raise_error(Dinie::AuthError)
    end

    it "raises PermissionDeniedError when exchange returns 403" do
      stub_cc(access_token: "cc-tok")
      stub_request(:post, exchange_url).to_return(
        status: 403, body: JSON.generate(type: "https://docs.dinie.com/errors/forbidden",
                                         detail: "forbidden")
      )

      expect { build_session_manager.access_token }.to raise_error(Dinie::PermissionDeniedError)
    end

    it "does NOT raise SessionTokenExpiredError on exchange failure (T9 vs T5 distinction)" do
      stub_cc
      stub_request(:post, exchange_url).to_return(status: 401, body: "{}")

      # AuthError (401 from exchange) — NOT SessionTokenExpiredError (which requires @exchanged=true)
      expect { build_session_manager.access_token }.to raise_error(Dinie::AuthError)
    end

    it "@exchanged stays false after exchange failure — next call re-attempts (not T5)" do
      stub_cc(access_token: "cc-tok")
      stub_request(:post, exchange_url)
        .to_return(status: 401, body: "{}")
        .then.to_return(status: 200, body: exchange_body(access_token: "cust-ok"))

      manager = build_session_manager
      expect { manager.access_token }.to raise_error(Dinie::AuthError)

      # Second call re-attempts the exchange (code still unexchanged) → now succeeds
      expect(manager.access_token).to eq("cust-ok")
    end

    it "does not cache the token when exchange fails" do
      stub_cc
      stub_request(:post, exchange_url).to_return(status: 401, body: "{}")

      manager = build_session_manager
      expect { manager.access_token }.to raise_error(Dinie::AuthError)

      # No token was cached — manager remains unauthenticated
      expect(
        a_request(:post, exchange_url)
      ).to have_been_made.once
    end

    it "single-flight unlocks after exchange failure — no deadlock on waiting callers" do
      # Each thread that wins the mutex will do its own two-step: cc POST + exchange POST.
      # The exchange always returns 401 immediately (no blocking gate), so waiting callers
      # each get a chance to retry and fail — no permanent lock.
      stub_request(:post, token_url).to_return(status: 200, body: cc_body)
      stub_request(:post, exchange_url).to_return(status: 401, body: "{}")

      manager = build_session_manager
      errors = []
      mutex = Mutex.new
      cond = ConditionVariable.new
      go = false
      threads = Array.new(3) do
        Thread.new do
          mutex.synchronize { cond.wait(mutex) until go }
          begin
            manager.access_token
          rescue => e # rubocop:disable Style/RescueStandardError
            errors << e
          end
        end
      end
      mutex.synchronize do
        go = true
        cond.broadcast
      end
      threads.each(&:join)

      expect(errors.size).to eq(3)
      expect(errors).to all(be_a(Dinie::AuthError))
    end
  end

  # ── mode symmetry: code=nil vs code=present ────────────────────────────────────────────────

  describe "mode symmetry" do
    it "code: nil is identical to omitting code (partner mode)" do
      stub_request(:post, token_url).to_return(status: 200, body: cc_body(access_token: "partner-tok"))

      manager = described_class.new(
        client_id: client_id, client_secret: client_secret,
        base_url: base_url, clock: clock, code: nil
      )
      expect(manager.access_token).to eq("partner-tok")
      expect(a_request(:post, exchange_url)).not_to have_been_made
    end
  end
end

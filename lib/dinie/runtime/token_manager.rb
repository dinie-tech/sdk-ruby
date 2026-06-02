# frozen_string_literal: true

require "base64"
require "faraday"
require "faraday/net_http_persistent"

module Dinie
  module Internal
    # `TokenManager` — the OAuth2 *client_credentials* token cache (architecture §10, RB-T,
    # `runtime-patterns.md` §4), porting `sdk-js` `src/runtime/token-manager.ts`. It acquires and
    # transparently refreshes the Bearer token every request rides on, speaking RFC 6749:
    #
    #   POST {base_url}/auth/token
    #   Authorization: Basic base64("{client_id}:{client_secret}")
    #   Content-Type:  application/x-www-form-urlencoded
    #   body:          grant_type=client_credentials
    #   → 200 { access_token, token_type: "bearer", expires_in }
    #
    # Three behaviours make it one of the risky-core modules:
    #
    #   1. **Proactive refresh** — the cached token is treated as stale {REFRESH_MARGIN_SECONDS}
    #      (300s) BEFORE its real expiry, so a live request never races the boundary.
    #   2. **Concurrency lock** — a `Mutex` + `ConditionVariable` (+ an `@refreshing` flag)
    #      serialize refreshes: N simultaneous `#access_token` callers trigger exactly ONE token
    #      POST. The claim ("I will refresh") is made UNDER the mutex, so it is impossible for two
    #      threads to both start a refresh; the losers park on the condition variable and, after a
    #      **double-check** on wake, return the freshly-cached token. The POST itself runs OUTSIDE
    #      the lock so a slow handshake never blocks the validity check.
    #   3. **401 invalidation** — `#invalidate!` drops the cached token. The 401 one-shot re-auth
    #      itself is orchestrated by {HttpClient} (story 003); this module only exposes the seam
    #      (`#access_token` / `#invalidate!`) and never loops on requests itself.
    #
    # ── DI seam (architecture §10, RB15) ──
    # This is the REAL token source {HttpClient} expects via its injected `token_manager:`
    # (`auth_headers` calls `#access_token`; the 401 one-shot calls `#invalidate!`). {Dinie::Client}
    # builds ONE `Faraday::Connection` and injects it into BOTH the HttpClient and this manager, so
    # the token POST rides the SAME connection pool as every other request — and, once story 005
    # mounts the logging middleware on that shared connection, the `Authorization: Basic` header
    # (which carries the client secret) is redacted there. URLs are absolute, so the connection's
    # `url_prefix` is irrelevant (mirrors {HttpClient}). A `connection:` is optional: standalone use
    # (and most specs) lets the manager build its own.
    #
    # ── runtime ↔ generated boundary ──
    # Lives in `runtime/`, imports only `errors` (for {Dinie::OAuthError}) + Faraday, and is NOT
    # part of the public barrel: {Dinie::Client}/{HttpClient} construct it internally.
    #
    # The ClassLength cop is disabled below: the token lifecycle (validity check → claim → POST →
    # parse → cache → wake) is one cohesive concurrency unit; splitting it would scatter the
    # invariant (the refresh claim and the cache mutation must share one mutex).
    class TokenManager # rubocop:disable Metrics/ClassLength
      # Bare token-endpoint path, appended to the configured base URL (which already carries the
      # `/api/v3` version prefix, so the full URL is `…/api/v3/auth/token`).
      TOKEN_PATH = "/auth/token"
      # Refresh the token this many SECONDS before its stated expiry (300s, `runtime-patterns.md`
      # §4). The margin absorbs clock skew and in-flight latency so a live request never carries a
      # token that expires mid-flight.
      REFRESH_MARGIN_SECONDS = 300
      # The fixed `application/x-www-form-urlencoded` body of the client_credentials grant.
      GRANT_BODY = "grant_type=client_credentials"
      # `Content-Type` of the token request.
      FORM_CONTENT_TYPE = "application/x-www-form-urlencoded"
      # OAuthError messages for a malformed token payload (kept as constants so the guard clauses
      # stay on one line and read cleanly).
      MISSING_ACCESS_TOKEN = 'OAuth2 token response was missing a valid "access_token".'
      # {Dinie::OAuthError} message for a token payload missing a valid `expires_in`.
      MISSING_EXPIRES_IN = 'OAuth2 token response was missing a valid "expires_in".'

      # @param client_id [String] OAuth2 client id (the Basic-auth username)
      # @param client_secret [String] OAuth2 client secret (the Basic-auth password)
      # @param base_url [String, nil] API base URL incl. the version prefix (default
      #   {HttpClient::DEFAULT_BASE_URL}); the bare {TOKEN_PATH} is appended to it
      # @param connection [Faraday::Connection, nil] injected shared connection (pool-sharing seam);
      #   `nil` builds a standalone one. Requests use absolute URLs, so `url_prefix` is irrelevant
      # @param refresh_margin_seconds [Integer] proactive-refresh margin (default
      #   {REFRESH_MARGIN_SECONDS}); parameterized for boundary tests
      # @param adapter [Symbol, nil] Faraday adapter for the standalone connection (default
      #   `:net_http_persistent`)
      # @param clock [#call, nil] monotonic-ish "seconds now" source (tests inject a controllable
      #   one to exercise the margin boundary); defaults to wall-clock seconds
      def initialize(client_id:, client_secret:, base_url: nil, connection: nil, # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength
                     refresh_margin_seconds: REFRESH_MARGIN_SECONDS, adapter: nil, clock: nil)
        @client_id = client_id
        @client_secret = client_secret
        @base_url = (base_url || HttpClient::DEFAULT_BASE_URL).sub(%r{/+\z}, "")
        @refresh_margin_seconds = refresh_margin_seconds
        @clock = clock || -> { ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) }
        @connection = connection || build_connection(adapter)

        @mutex = Mutex.new
        @condition = ConditionVariable.new
        @refreshing = false
        @access_token = nil
        @expires_at = nil
      end

      # Return a valid Bearer access token, acquiring or refreshing transparently.
      #
      # Fast path: a cached token still inside the margin is returned without a request. Otherwise
      # the FIRST caller claims the refresh under the mutex and runs the POST outside it; concurrent
      # callers park on the condition variable and, after a double-check on wake, return the
      # freshly-cached token. Under N concurrent callers exactly ONE token POST occurs.
      #
      # @return [String] a valid OAuth2 access token
      # @raise [Dinie::OAuthError] the token handshake failed (transport, non-2xx, or malformed body)
      def access_token
        @mutex.synchronize do
          loop do
            return @access_token if token_valid?
            break unless @refreshing

            # Another thread is already refreshing — park until it broadcasts, then re-check
            # (double-check pattern): it may have populated the cache, or its refresh may have failed.
            @condition.wait(@mutex)
          end
          @refreshing = true # claim the refresh (under the mutex — only one thread can win)
        end

        refresh_and_cache
      end

      # Drop the cached token so the next {#access_token} re-authenticates. Called by {HttpClient}
      # on a 401 (the one-shot re-auth is orchestrated there). Takes the mutex so it never races a
      # concurrent validity check.
      #
      # @return [void]
      def invalidate!
        @mutex.synchronize do
          @access_token = nil
          @expires_at = nil
        end
      end

      private

      # True when a token is cached and still outside the refresh margin. Only ever called under
      # the mutex, so reading `@access_token`/`@expires_at` together is race-free.
      def token_valid?
        !@access_token.nil? && now < @expires_at - @refresh_margin_seconds
      end

      # Run the refresh OUTSIDE the mutex (the POST is I/O — holding the lock would block the
      # validity check for every other caller). Whatever happens, the `ensure` clears the claim and
      # wakes the parked threads, so a failed handshake never leaves a permanently-stuck lock: the
      # next waiter re-checks, finds no token, and retries.
      def refresh_and_cache # rubocop:disable Metrics/MethodLength
        access_token, expires_at = fetch_token
        @mutex.synchronize do
          @access_token = access_token
          @expires_at = expires_at
        end
        access_token
      ensure
        @mutex.synchronize do
          @refreshing = false
          @condition.broadcast
        end
      end

      # Perform the token POST and return `[access_token, absolute_expiry_seconds]`. Anchors the
      # expiry on "now" AFTER the response lands so the margin math holds regardless of latency.
      def fetch_token
        response = request_token
        raise Dinie::OAuthError, status_failure(response.status, body_detail(response)) unless success?(response.status)

        access_token, expires_in = parse_token_response(response.body)
        [access_token, now + expires_in]
      end

      # One Faraday round-trip to the token endpoint. Absolute URL ⇒ the connection's `url_prefix`
      # is irrelevant. A transport failure (DNS, refused, timeout) becomes {Dinie::OAuthError}.
      def request_token
        @connection.run_request(:post, token_url, GRANT_BODY, token_request_headers)
      rescue Faraday::Error => e
        raise Dinie::OAuthError, "OAuth2 token request failed before a response was received: #{e.message}"
      end

      # Validate + extract the wire payload, returning `[access_token, expires_in]`. `token_type` is
      # intentionally ignored: {HttpClient} always sends `Authorization: Bearer …`, so the wire
      # value is informational. Any shape problem raises {Dinie::OAuthError}.
      def parse_token_response(raw_body)
        parsed = parse_json(raw_body)
        raise Dinie::OAuthError, "OAuth2 token response was not a JSON object." unless parsed.is_a?(Hash)

        access_token = parsed[:access_token]
        expires_in = parsed[:expires_in]
        raise Dinie::OAuthError, MISSING_ACCESS_TOKEN unless valid_access_token?(access_token)
        raise Dinie::OAuthError, MISSING_EXPIRES_IN unless valid_expires_in?(expires_in)

        [access_token, expires_in]
      end

      def parse_json(raw_body)
        JSON.parse(raw_body.to_s, symbolize_names: true)
      rescue JSON::ParserError
        raise Dinie::OAuthError, "OAuth2 token response body was not valid JSON."
      end

      def valid_access_token?(value)
        value.is_a?(String) && !value.empty?
      end

      def valid_expires_in?(value)
        value.is_a?(Numeric) && value.positive?
      end

      def token_request_headers
        {
          "authorization" => "Basic #{basic_credentials}",
          "content-type" => FORM_CONTENT_TYPE,
          "accept" => "application/json"
        }
      end

      # Base64 (RFC 4648) of `client_id:client_secret`, no line breaks (HTTP Basic).
      def basic_credentials
        Base64.strict_encode64("#{@client_id}:#{@client_secret}")
      end

      def token_url
        "#{@base_url}#{TOKEN_PATH}"
      end

      def success?(status)
        (200..299).cover?(status)
      end

      # Best-effort body text for a non-2xx failure message (never raises).
      def body_detail(response)
        response.body.to_s.strip
      rescue StandardError
        ""
      end

      def status_failure(status, detail)
        suffix = detail.empty? ? "" : ": #{detail}"
        "OAuth2 token request failed with status #{status}#{suffix}"
      end

      def now
        @clock.call
      end

      # Standalone fallback connection (production injects the shared one from {Dinie::Client}).
      # No logger seam here: the canonical, logged connection is the Client's shared one.
      def build_connection(adapter)
        Faraday.new(url: @base_url) do |faraday|
          faraday.adapter(adapter || :net_http_persistent)
        end
      end
    end
  end
end

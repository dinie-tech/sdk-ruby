# frozen_string_literal: true

require "json"
require "uri"
require "faraday"
require "faraday/multipart"
require "faraday/net_http_persistent"
require_relative "multipart"

module Dinie
  module Internal
    # `HttpClient` — the request-lifecycle orchestrator and heart of the runtime (architecture
    # §10, RB15), porting `sdk-js` `src/runtime/http.ts`. It owns one `Faraday::Connection` per
    # {Dinie::Client} (adapter `:net_http_persistent` — a real connection pool with keep-alive,
    # thread-safe) and, for every logical request, runs the full lifecycle:
    #
    #   1. mint an `X-Idempotency-Key` ONCE, before the loop, for non-GET writes, so every
    #      retry of the same logical request reuses it (never a duplicate resource);
    #   2. obtain a Bearer token from the injected `TokenManager`;
    #   3. assemble headers (auth, telemetry, idempotency, retry-count, content-type);
    #   4. dispatch through Faraday — **one round-trip per call**; the retry loop is ours;
    #   5. fold `X-RateLimit-*` headers into the snapshot `client.rate_limit` reads;
    #   6. on success (< 300), parse and return the raw body (resources deserialize);
    #   7. on 401, run the one-shot re-auth (`token_manager.invalidate!` + a fresh token), then
    #      give up with `AuthError` if a second 401 follows (no loop);
    #   8. on a retryable status (`{408,429,500,502,503,504}`) or a transient transport error,
    #      back off (`Retry.retry_delay`) and retry while attempts remain, bumping
    #      `X-Dinie-Retry-Count`;
    #   9. otherwise map the response to a typed error via {Errors.from_response}.
    #
    # ── DI seam (architecture §10, RB15) ──
    # The `TokenManager` is **injected** (`HttpClient.new(token_manager:, …)`). Story 004 builds
    # the real, concurrency-safe one; specs inject a fake. `auth_headers` is `token_manager
    # .access_token`; the 401 one-shot is `token_manager.invalidate!`. No global/singleton, no
    # placeholder hack — this is what lets `with_options` (story 004) clone a client while
    # sharing the same token cache.
    #
    # ── controlled runtime → generated seam (openapi-SoT forcing function, architecture §4) ──
    # The rule is "runtime/ never imports generated/". This module is one declared exception:
    # it references {Dinie::AuthError} (forced on a persistent 401) and dispatches non-2xx
    # responses through {Errors.from_response}, which reads the **generated**
    # {Dinie::Internal::ERROR_REGISTRY}. The reference is the forcing function — an error not in
    # `openapi.yaml` is not in `generated/`, so there is nowhere to dispatch it.
    #
    # Runtime-internal: {Dinie::Client} and the resources construct and call it; it is not part
    # of the public SDK surface.
    #
    # The ClassLength cop is disabled below: the request lifecycle (prepare → loop → dispatch →
    # error/retry/re-auth → parse) is one cohesive orchestrator; splitting it across classes would
    # scatter the lifecycle and obscure the parity with `sdk-js` `http.ts`.
    class HttpClient # rubocop:disable Metrics/ClassLength
      # Default production API base URL — carries the `/api/v3` version prefix (openapi
      # `servers[0]`). Resource paths are bare (`/customers`), so the version lives here.
      DEFAULT_BASE_URL = "https://api.dinie.com/api/v3"
      # Default per-request timeout, in **seconds** (RB17 — Faraday idiom; the TS SDK uses ms).
      DEFAULT_TIMEOUT_SECONDS = 30
      # Default retry budget after the first attempt.
      DEFAULT_MAX_RETRIES = 3
      # API version sourced from the generated constant (keeps telemetry in sync with the spec).
      API_VERSION = Dinie::Generated::API_VERSION
      # `Content-Type` for JSON request bodies.
      JSON_CONTENT_TYPE = "application/json"
      # Methods that auto-carry an `X-Idempotency-Key` when the caller does not say otherwise.
      AUTO_IDEMPOTENT_METHODS = %i[post patch].freeze
      # `User-Agent` sent on every request (architecture §5.1, telemetry AC).
      USER_AGENT = "Dinie-SDK-Ruby/#{Dinie::VERSION} (api-version=#{API_VERSION}; ruby/#{RUBY_VERSION})".freeze

      # Normalized, per-call request descriptor threaded through the retry loop. Keeping it in
      # one struct holds the helper signatures small (and the body is serialized once, up front).
      # `http_method` (not `method`) avoids shadowing `Object#method`.
      PreparedRequest = Struct.new(
        :http_method, :url, :body, :content_type, :idempotency_key, :max_retries, :timeout, :header_overrides,
        keyword_init: true
      )
      private_constant :PreparedRequest

      # @param token_manager [#access_token, #invalidate!] injected OAuth2 token source (story 004)
      # @param base_url [String, nil] API base URL (default {DEFAULT_BASE_URL})
      # @param timeout [Numeric] per-request timeout in seconds (default {DEFAULT_TIMEOUT_SECONDS})
      # @param max_retries [Integer] retry budget after the first attempt (default {DEFAULT_MAX_RETRIES})
      # @param idempotency [Boolean] auto-generate `X-Idempotency-Key` on POST/PATCH (default true)
      # @param adapter [Symbol, nil] Faraday adapter (default `:net_http_persistent`)
      # @param connection [Faraday::Connection, nil] injected connection (pool-sharing/test seam);
      #   requests use absolute URLs, so its `url_prefix` is irrelevant
      # @param sleeper [#call, nil] backoff sleep (tests inject an instant, recording spy)
      def initialize(token_manager:, base_url: nil, timeout: DEFAULT_TIMEOUT_SECONDS, # rubocop:disable Metrics/ParameterLists
                     max_retries: DEFAULT_MAX_RETRIES, idempotency: true, adapter: nil,
                     connection: nil, sleeper: nil)
        @token_manager = token_manager
        @base_url = (base_url || DEFAULT_BASE_URL).sub(%r{/+\z}, "")
        @timeout = timeout
        @max_retries = max_retries
        @idempotency = idempotency
        @rate_limit_tracker = RateLimitTracker.new
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @connection = connection || build_connection(adapter)
      end

      # Latest rate-limit snapshot (read by `client.rate_limit`); `nil` before the first
      # response that carried valid `X-RateLimit-*` headers.
      #
      # @return [Dinie::RateLimit, nil]
      def rate_limit
        @rate_limit_tracker.snapshot
      end

      # Run one logical request end-to-end and return the parsed body (resources deserialize it).
      # `204`/empty bodies return `nil`; a JSON body is parsed with symbol keys; a non-JSON body
      # is returned as raw text.
      #
      # @param method [Symbol, String] HTTP method (`:get`, `:post`, `:patch`, `:delete`, …)
      # @param path [String] bare resource path (e.g. `/customers`); the base URL adds `/api/v3`
      # @param query [Hash, nil] query params (`nil` values are dropped)
      # @param body [Object, nil] request body (Hash/Array → JSON; String passed through)
      # @param idempotent [Boolean, nil] force/suppress the idempotency key; `nil` ⇒ auto on POST/PATCH
      # @param request_options [Dinie::Internal::RequestOptions, Hash, nil] per-call overrides
      # @return [Object, nil] the parsed response body
      # @raise [Dinie::APIStatusError] a typed error for any non-2xx that is not retried
      # @raise [Dinie::AuthError] a 401 that persists after the one-shot re-auth
      # @raise [Dinie::APITimeoutError] the request timed out and the retry budget is exhausted
      # @raise [Dinie::APIConnectionError] a transport failure
      def request(method:, path:, query: nil, body: nil, idempotent: nil, request_options: nil) # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        options = RequestOptions.coerce(request_options)
        normalized_method = method.to_s.downcase.to_sym
        serialized_body, content_type = serialize_body(body)
        execute(PreparedRequest.new(
                  http_method: normalized_method,
                  url: build_full_url(path, query),
                  body: serialized_body,
                  content_type: content_type,
                  idempotency_key: resolve_idempotency_key(idempotent, normalized_method, options),
                  max_retries: options.max_retries || @max_retries,
                  timeout: options.timeout || @timeout,
                  header_overrides: options.headers
                ))
      end

      private

      # The retry loop. `attempt` increments on every continued path (a transport retry, a
      # status retry, AND the 401 one-shot), so `X-Dinie-Retry-Count` mirrors the TS SDK exactly.
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
      def execute(prepared)
        attempt = 0
        reauthed = false
        loop do
          token = @token_manager.access_token
          headers = build_headers(prepared, token, attempt)

          begin
            response = dispatch(prepared, headers)
          rescue Faraday::Error => e
            raise translate_network_error(e) unless Retry.retryable_network_error?(e) && attempt < prepared.max_retries

            sleep_for(Retry.retry_delay(attempt))
            attempt += 1
            next
          end

          @rate_limit_tracker.update(response.headers)
          status = response.status
          return parse_body(response) if status < 300

          # 401 one-shot: drop the cached token, re-auth once, retry.
          if status == 401 && !reauthed
            @token_manager.invalidate!
            reauthed = true
            attempt += 1
            next
          end
          # Persistent 401 after the one-shot: give up with a typed AuthError (no loop). Forcing
          # the class guarantees the type even if the body lacks the openapi `type` URL.
          raise build_error(response, force: Dinie::AuthError) if status == 401

          if Retry.should_retry?(status) && attempt < prepared.max_retries
            sleep_for(Retry.retry_delay(attempt,
                                        retry_after: header(response, "retry-after"),
                                        retry_after_ms: header(response, "retry-after-ms")))
            attempt += 1
            next
          end

          raise build_error(response)
        end
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength

      # One Faraday round-trip. Absolute URL ⇒ the connection's `url_prefix` is irrelevant, so
      # `base_url='…/api/v3'` never collides with a leading-slash resource path.
      def dispatch(prepared, headers)
        @connection.run_request(prepared.http_method, prepared.url, prepared.body, headers) do |req|
          req.options.timeout = prepared.timeout
          req.options.open_timeout = prepared.timeout
        end
      end

      # Assemble the outgoing headers: Bearer auth, telemetry, the Idempotency-Key (when
      # present), `X-Dinie-Retry-Count` on retries, and `Content-Type` when there is a body. A
      # caller header with a `nil` value removes the matching default; any other value overrides.
      def build_headers(prepared, token, attempt)
        headers = base_headers(token)
        headers["content-type"] = prepared.content_type unless prepared.content_type.nil?
        headers["x-idempotency-key"] = prepared.idempotency_key unless prepared.idempotency_key.nil?
        headers["x-dinie-retry-count"] = attempt.to_s if attempt.positive?
        apply_header_overrides(headers, prepared.header_overrides)
      end

      # Auth + telemetry defaults present on every request (architecture §5.1).
      def base_headers(token)
        {
          "authorization" => "Bearer #{token}",
          "accept" => JSON_CONTENT_TYPE,
          "user-agent" => USER_AGENT,
          "x-dinie-sdk-language" => "ruby",
          "x-dinie-sdk-version" => Dinie::VERSION,
          "x-dinie-sdk-runtime" => "ruby/#{RUBY_VERSION}"
        }
      end

      # Apply per-call header overrides: `nil` removes a default, any String replaces it.
      def apply_header_overrides(headers, overrides)
        return headers if overrides.nil?

        overrides.each do |key, value|
          lower = key.to_s.downcase
          if value.nil?
            headers.delete(lower)
          else
            headers[lower] = value
          end
        end
        headers
      end

      # Resolve the `X-Idempotency-Key` (architecture §10). A per-call override always wins —
      # even when auto-idempotency is opted out globally, an explicit key is an explicit opt-in.
      # Otherwise a key is auto-minted for POST/PATCH unless opted out. `nil` ⇒ send no key.
      def resolve_idempotency_key(idempotent, method, options)
        idempotent = AUTO_IDEMPOTENT_METHODS.include?(method) if idempotent.nil?
        return nil unless idempotent
        return options.idempotency_key unless options.idempotency_key.nil?
        return nil unless @idempotency

        Idempotency.generate_key
      end

      # Serialize a request body: a {Multipart} becomes a Faraday multipart body tagged with a bare
      # `multipart/form-data` content type (Faraday's `:multipart` middleware appends the boundary
      # and encodes it — story 009); a Hash/Array → JSON; a String is assumed already-serialized
      # JSON; `nil` sends no body. Returns `[body_or_nil, content_type_or_nil]`.
      def serialize_body(body)
        return [nil, nil] if body.nil?
        return [body.to_faraday_body, Multipart::CONTENT_TYPE] if body.is_a?(Multipart)
        return [body, JSON_CONTENT_TYPE] if body.is_a?(String)

        [JSON.generate(body), JSON_CONTENT_TYPE]
      end

      # Read + parse a successful response body. `204`/empty ⇒ `nil`; JSON ⇒ parsed with symbol
      # keys (resources read `raw[:field]`); non-JSON ⇒ raw text.
      def parse_body(response)
        return nil if response.status == 204

        body = response.body
        return nil if body.nil? || body.empty?

        JSON.parse(body, symbolize_names: true)
      rescue JSON::ParserError
        body
      end

      # Prepend the base URL and append the query string. Absolute URLs sidestep Faraday's
      # leading-slash base-path replacement (the trap `sdk-js` handles via `#basePath`).
      def build_full_url(path, query)
        url = "#{@base_url}#{path}"
        encoded = encode_query(query)
        return url if encoded.empty?

        "#{url}#{path.include?("?") ? "&" : "?"}#{encoded}"
      end

      # Encode query params, dropping `nil` values.
      def encode_query(query)
        return "" if query.nil? || query.empty?

        URI.encode_www_form(query.compact)
      end

      # First value of a (possibly repeated) response header.
      def header(response, name)
        value = response.headers[name]
        value.is_a?(Array) ? value.first : value
      end

      # Build the typed error for a non-2xx response (story 002 dispatch). `body` is the raw
      # String (JSON is parsed inside `from_response`); `force` skips dispatch (persistent 401).
      def build_error(response, force: nil)
        Errors.from_response(status: response.status, headers: response.headers.to_h,
                             body: response.body, force: force)
      end

      # Map an exhausted/non-retryable transport error to the right connection-error class.
      def translate_network_error(error)
        return Dinie::APITimeoutError.new if error.is_a?(Faraday::TimeoutError)

        Dinie::APIConnectionError.new(error.message)
      end

      def sleep_for(seconds)
        @sleeper.call(seconds)
      end

      # Standalone fallback connection, used only when no `connection:` is injected (tests, direct
      # use). The composed SDK always injects the SHARED connection built by {Dinie::Client}, which
      # is where the story 005 logging middleware mounts (so it also observes the TokenManager's
      # token POST). This builder is intentionally plain — do NOT mount logging here.
      def build_connection(adapter)
        Faraday.new(url: @base_url) do |faraday|
          faraday.request(:multipart)
          faraday.adapter(adapter || :net_http_persistent)
        end
      end
    end
  end
end

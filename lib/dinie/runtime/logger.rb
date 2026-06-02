# frozen_string_literal: true

require "json"
require "logger"
require "set"
require "securerandom"
require "faraday"
require_relative "model"

module Dinie
  module Internal
    # Pure, stateless redaction + truncation helpers shared by {RuntimeLogger}. A financial
    # backend carries PII and credentials in headers and bodies, so every value the logger emits
    # passes through here first (architecture §9, RB12). No I/O, no state — trivially testable.
    #
    # The body-field redaction list is **derived from** {Dinie::Internal::Model::REDACTED_ATTRIBUTES}
    # (story 002) so the logger and the model `#inspect` can never drift apart: one source of truth
    # for "what counts as PII" (the story's stated risk — divergence here is a leak).
    module LogRedaction
      # Mask substituted for any redacted header value or body field.
      REDACTED = "[REDACTED]"
      # Bodies whose serialized size reaches this many bytes are truncated (architecture §9).
      MAX_BODY_BYTES = 2048
      # Header names (lowercased) whose values carry credentials/signatures → masked. Covers the
      # `Authorization: Basic` of the token POST (client secret), the webhook HMAC, the per-call
      # client-secret header, and any forward-proxy auth.
      REDACTED_HEADERS = Set.new(
        %w[authorization webhook-signature x-dinie-client-secret proxy-authorization]
      ).freeze
      # Body field names (lowercased) carrying PII/secrets → masked recursively. Mirrors the
      # model's `#inspect` redaction set verbatim (the canonical list, story 002).
      REDACTED_BODY_FIELDS = Set.new(Model::REDACTED_ATTRIBUTES.map(&:to_s)).freeze

      # Sentinel telling {format_body} that a String body was not JSON (so it is logged as-is,
      # not re-serialized). Distinct from a real JSON `null`, which parses to `nil`.
      NOT_JSON = Object.new
      private_constant :NOT_JSON

      module_function

      # Replace the value of any sensitive header with the mask (case-insensitive). Accepts a Hash
      # or `Faraday::Utils::Headers`; returns a plain Hash with the original key casing preserved.
      #
      # @param headers [#each, nil] request/response headers
      # @return [Hash{String => Object}]
      def redact_headers(headers)
        return {} if headers.nil?

        headers.each_with_object({}) do |(key, value), out|
          out[key.to_s] = REDACTED_HEADERS.include?(key.to_s.downcase) ? REDACTED : value
        end
      end

      # Deep-copy `value`, masking any Hash key (case-insensitive) that names a PII/secret field.
      # Arrays and nested objects are walked; scalars pass through untouched.
      #
      # @param value [Object] a parsed body (Hash/Array/scalar)
      # @return [Object] the redacted copy
      def redact_body(value)
        case value
        when Array then value.map { |item| redact_body(item) }
        when Hash then redact_hash(value)
        else value
        end
      end

      # @api private
      def redact_hash(hash)
        hash.each_with_object({}) do |(key, value), out|
          out[key] = REDACTED_BODY_FIELDS.include?(key.to_s.downcase) ? REDACTED : redact_body(value)
        end
      end

      # Render a body for logging: redact PII, serialize to JSON, then truncate. A String body is
      # JSON-parsed first (so its fields are redacted) and logged verbatim when it is not JSON.
      # `nil`/empty bodies return `nil` (the caller drops the key).
      #
      # @param body [Object, nil] the raw request/response body
      # @return [String, nil]
      def format_body(body)
        return nil if body.nil? || (body.is_a?(String) && body.empty?)

        truncate_body(serialize_for_log(body))
      end

      # @api private
      def serialize_for_log(body)
        return safe_generate(redact_body(body)) unless body.is_a?(String)

        parsed = parse_json(body)
        parsed.equal?(NOT_JSON) ? body : safe_generate(redact_body(parsed))
      end

      # Truncate to {MAX_BODY_BYTES} on a codepoint boundary, appending `…[truncated,
      # full_size=NNN]` (NNN = full UTF-8 byte size). Returns the input unchanged when under the
      # threshold (so a binary/multipart blob never floods the log — story risk note).
      #
      # @param text [String]
      # @return [String]
      def truncate_body(text)
        full_size = text.bytesize
        return text if full_size < MAX_BODY_BYTES

        "#{clip_to_bytes(text, MAX_BODY_BYTES)}…[truncated, full_size=#{full_size}]"
      end

      # @api private
      # Take whole characters until the next one would exceed `max_bytes`.
      def clip_to_bytes(text, max_bytes)
        bytes = 0
        clipped = +""
        text.each_char do |char|
          char_bytes = char.bytesize
          break if bytes + char_bytes > max_bytes

          bytes += char_bytes
          clipped << char
        end
        clipped
      end

      # @api private
      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        NOT_JSON
      end

      # @api private
      # `JSON.generate` that never raises (a log line must not blow up the request).
      def safe_generate(value)
        JSON.generate(value)
      rescue StandardError
        "[unserializable]"
      end
    end

    # Leveled logging facade with PII redaction (architecture §9, RB12). Owns the effective level
    # (resolved once) and an injectable sink; gates every call and routes request/response detail
    # through {LogRedaction} before emitting. Constructed by {Middleware::Logging} from the
    # `log_level:` / `logger:` the {Dinie::Client} captured.
    #
    # Defaults to `:off` — a financial SDK emits nothing unless the caller opts in. Mirrors the
    # leveling/redaction approach of the TS `RuntimeLogger`; the divergence is the **hook point**
    # (TS owns a custom logger instance; Ruby fills the OpenAI-Ruby gap with a Faraday middleware —
    # the `comparison.md` axis).
    class RuntimeLogger
      # Level ordering for gating: a call at `level` emits when `level <= configured` (so `:off`
      # emits nothing, `:debug` emits everything).
      LEVELS = { off: 0, error: 1, warn: 2, info: 3, debug: 4 }.freeze
      # Environment variable read when no explicit `level:` is given.
      ENV_VAR = "DINIE_LOG"

      # The effective level after `level:` + `DINIE_LOG` resolution.
      # @return [Symbol]
      attr_reader :level

      # @param level [Symbol, String, nil] explicit level; a valid one wins over the env var
      # @param logger [Object, nil] custom sink responding to `#debug/#info/#warn/#error`
      #   (default `::Logger.new($stdout)`)
      # @param env [String, nil] `DINIE_LOG` override (injectable for tests)
      def initialize(level: nil, logger: nil, env: ENV.fetch(ENV_VAR, nil))
        @level = resolve_level(level, env)
        @sink = logger || ::Logger.new($stdout)
      end

      # Whether a call at `level` would emit under the configured level.
      #
      # @param level [Symbol] one of {LEVELS}
      # @return [Boolean]
      def enabled?(level)
        LEVELS.fetch(level) <= LEVELS.fetch(@level)
      end

      # @return [void]
      def error(message) = emit(:error, message)
      # @return [void]
      def warn(message) = emit(:warn, message)
      # @return [void]
      def info(message) = emit(:info, message)
      # @return [void]
      def debug(message) = emit(:debug, message)

      # Log an outgoing request at `debug` with redacted headers + body and the correlation triple.
      #
      # @param method [Symbol, String] HTTP method
      # @param url [String] request URL
      # @param headers [#each, nil] request headers
      # @param body [Object, nil] request body
      # @param correlation [Hash] `request_log_id` / `retry_of` / `attempt`
      # @return [void]
      def log_request(method:, url:, headers:, body:, correlation:)
        return unless enabled?(:debug)

        emit_line("→ request", correlation.merge(method: method.to_s.upcase, url: url), headers, body)
      end

      # Log an incoming response at `debug` with redacted headers + body, duration, and request id.
      #
      # @param status [Integer] HTTP status
      # @param url [String] request URL
      # @param headers [#each, nil] response headers
      # @param body [Object, nil] response body
      # @param duration_ms [Float] round-trip time in milliseconds
      # @param request_id [String, nil] the response `X-Request-Id` (APM correlation)
      # @param correlation [Hash] `request_log_id` / `retry_of` / `attempt`
      # @return [void]
      def log_response(status:, url:, headers:, body:, duration_ms:, request_id:, correlation:) # rubocop:disable Metrics/ParameterLists
        return unless enabled?(:debug)

        fields = correlation.merge(status: status, url: url, duration_ms: duration_ms, request_id: request_id)
        emit_line("← response", fields, headers, body)
      end

      private

      def emit(level, message)
        @sink.public_send(level, message) if enabled?(level)
      end

      # Render one debug line as `[dinie] <label> k=v … headers={…} body=<json>`. Scalar fields use
      # `k=v`; headers are inspected (a small map); the body is appended RAW (the already-redacted,
      # truncated JSON) so it is not double-escaped — readable in logs and grep-able in tests.
      def emit_line(label, fields, headers, body)
        parts = ["[dinie] #{label}"]
        fields.compact.each { |key, value| parts << "#{key}=#{value}" }
        parts << "headers=#{LogRedaction.redact_headers(headers).inspect}" unless headers.nil?
        formatted = LogRedaction.format_body(body)
        parts << "body=#{formatted}" unless formatted.nil?
        @sink.debug(parts.join(" "))
      end

      # Explicit valid `level:` wins; else a valid `DINIE_LOG`; else `:off`. An unset/garbage value
      # never raises — it degrades to `:off`.
      def resolve_level(level, env)
        return level.to_sym if valid_level?(level)
        return env.strip.to_sym if !env.nil? && valid_level?(env.strip)

        :off
      end

      def valid_level?(value)
        !value.nil? && LEVELS.key?(value.to_s.to_sym)
      end
    end

    # Namespace for the SDK's Faraday middleware (currently just {Middleware::Logging}).
    module Middleware
      # `Logging` — the Faraday response middleware that makes logging the natural hook point
      # (architecture §9, RB12), filling the gap OpenAI Ruby leaves (no logger at all). {Dinie::Client}
      # mounts it on the ONE shared connection, BEFORE the adapter, so it observes the FINAL
      # request/response of EVERY call — including the {TokenManager}'s `POST /auth/token`, whose
      # `Authorization: Basic` header (the client secret) is redacted here automatically.
      #
      # ── Retry correlation across a Faraday-level middleware ──
      # The retry loop lives ABOVE this middleware (in {HttpClient}), so each attempt is a separate
      # round-trip through `#call`. To still stitch a request and its retries together in an APM, the
      # first attempt (no `X-Dinie-Retry-Count`) mints an origin `request_log_id` and stashes it on
      # the current thread; each retry — run synchronously in that SAME thread by the retry loop —
      # reports `retry_of: <origin>`. This is the Ruby manifestation of the TS logger's
      # `requestLogID`/`retryOf`, adapted to the middleware hook point.
      class Logging < Faraday::Middleware
        # Thread-local key holding the origin request's log id for the current logical request.
        ORIGIN_LOG_ID_KEY = :__dinie_origin_request_log_id
        # Request header {HttpClient} sets on retried attempts (`"1"`, `"2"`, …); absent on the first.
        RETRY_COUNT_HEADER = "x-dinie-retry-count"
        # Response header carrying the server-side request id (architecture §7 — `err.request_id`).
        REQUEST_ID_HEADER = "x-request-id"

        # @param app [#call] the next middleware/adapter in the stack
        # @param level [Symbol, String, nil] log level (forwarded to {RuntimeLogger})
        # @param logger [Object, nil] custom sink (forwarded to {RuntimeLogger})
        def initialize(app, level: nil, logger: nil)
          super(app)
          @logger = RuntimeLogger.new(level: level, logger: logger)
        end

        # @param request_env [Faraday::Env]
        # @return [Faraday::Response]
        def call(request_env)
          correlation = correlate(request_env.request_headers)
          log_request(request_env, correlation)
          started = monotonic_now
          @app.call(request_env).on_complete do |response_env|
            log_response(response_env, correlation, started)
          end
        end

        private

        def log_request(env, correlation)
          @logger.log_request(method: env.method, url: env.url.to_s,
                              headers: env.request_headers, body: env.body, correlation: correlation)
        end

        def log_response(env, correlation, started)
          @logger.log_response(status: env.status, url: env.url.to_s,
                               headers: env.response_headers, body: env.body,
                               duration_ms: elapsed_ms(started), request_id: env.response_headers[REQUEST_ID_HEADER],
                               correlation: correlation)
        end

        # Build the `request_log_id` / `retry_of` / `attempt` triple (see the class doc for the
        # thread-local rationale).
        def correlate(request_headers)
          attempt = request_headers[RETRY_COUNT_HEADER].to_i
          request_log_id = "req_#{SecureRandom.hex(6)}"
          if attempt.zero?
            Thread.current[ORIGIN_LOG_ID_KEY] = request_log_id
            { request_log_id: request_log_id, retry_of: nil, attempt: attempt }
          else
            { request_log_id: request_log_id, retry_of: Thread.current[ORIGIN_LOG_ID_KEY], attempt: attempt }
          end
        end

        def monotonic_now
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end

        def elapsed_ms(started)
          ((monotonic_now - started) * 1000).round(1)
        end
      end
    end
  end
end

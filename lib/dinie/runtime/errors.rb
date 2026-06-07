# frozen_string_literal: true

require "json"
require "time"

module Dinie
  # Root of every error the SDK raises.
  class Error < StandardError; end

  # Base for everything that originates from talking to the Dinie API.
  #
  # `code` and `request_id` are first-class here so every API error answers them (a
  # connection error simply carries `nil`). The extraction logic that reads them off the
  # RFC 9457 body / response headers lives once in {APIStatusError}, never per marker
  # class — mirroring the V0.2 freeze and the future generator's "emit once into the base".
  class APIError < Error
    # @return [String, nil] machine-readable error code from the Problem Details `code` extension
    attr_reader :code

    # @return [String, nil] per-request correlation id (from `x-request-id`, body fallback)
    attr_reader :request_id

    # @param message [String, nil]
    # @param code [String, nil]
    # @param request_id [String, nil]
    def initialize(message = nil, code: nil, request_id: nil)
      super(message)
      @code = code
      @request_id = request_id
    end
  end

  # A request never produced a response (DNS failure, socket reset, timeout…). Client-side:
  # there is no server response to describe, so it lives in `runtime/`.
  class APIConnectionError < APIError
    # @param message [String]
    def initialize(message = "Connection error.")
      super
    end
  end

  # The request exceeded the configured timeout.
  class APITimeoutError < APIConnectionError
    # @param message [String]
    def initialize(message = "Request timed out.")
      super
    end
  end

  # The API returned a non-2xx response. Base of the openapi-mirrored marker catalog
  # (`generated/errors/registry.rb`); the markers are empty subclasses and inherit this
  # constructor, so {Internal::Errors.from_response} can build any of them uniformly.
  class APIStatusError < APIError
    # @return [Integer] HTTP status code
    attr_reader :status
    # @return [Hash] raw response headers
    attr_reader :headers
    # @return [Hash, String, nil] parsed Problem Details, raw body text, or nil
    attr_reader :body
    # @return [String, nil] Problem Details `type` URL
    attr_reader :type
    # @return [String, nil] Problem Details `title`
    attr_reader :title
    # @return [String, nil] Problem Details `detail`
    attr_reader :detail
    # @return [String, nil] Problem Details `instance`
    attr_reader :instance

    # @param status [Integer]
    # @param body [Hash, String, nil] parsed Problem Details (symbol keys), raw text, or nil
    # @param headers [Hash]
    # @param request_id [String, nil]
    def initialize(status:, body:, headers:, request_id: nil)
      @status = status
      @headers = headers
      @body = body
      problem = body.is_a?(Hash) ? body : nil
      @type = string_field(problem, :type)
      @title = string_field(problem, :title)
      @detail = string_field(problem, :detail)
      @instance = string_field(problem, :instance)
      super(self.class.build_message(status, body, request_id),
            code: string_field(problem, :code), request_id: request_id)
    end

    # @api private
    # @return [String]
    def self.build_message(status, body, request_id)
      summary = message_summary(body)
      suffix = request_id.nil? ? "" : " (request_id: #{request_id})"
      summary ? "#{status} #{summary}#{suffix}" : "#{status} status code (no body)#{suffix}"
    end

    # @api private
    def self.message_summary(body)
      if body.is_a?(Hash)
        body[:detail] || body[:title]
      elsif body.is_a?(String) && !body.empty?
        body
      end
    end
    private_class_method :message_summary

    private

    def string_field(problem, key)
      return nil unless problem

      value = problem[key]
      value.is_a?(String) ? value : nil
    end
  end

  # ── Client-side errors (outside the APIError tree — no server response) ────────

  # OAuth2 client-credentials token acquisition/refresh failed.
  class OAuthError < Error; end

  # A session-mode token was successfully exchanged once but has since expired (via
  # {Dinie::Internal::TokenManager#invalidate!} or TTL). Session tokens are single-use:
  # once expired the original authorization code cannot be re-exchanged. Callers should
  # surface this to the consumer so they can obtain a fresh code.
  class SessionTokenExpiredError < Error; end

  # A webhook payload failed HMAC signature verification.
  class WebhookSignatureError < Error; end

  # A webhook timestamp fell outside the tolerance window.
  class WebhookTimestampError < Error; end

  # A webhook signature verified, but the payload's `type` is not in the openapi event
  # catalog, so there is no per-type deserializer for it. Raising (rather than passing the
  # raw event through) is deliberate — a new event `type` is a contract change. The
  # unrecognized `type` is preserved on {#event_type}.
  class UnknownWebhookEventError < Error
    # @return [String] the unrecognized (but verified) webhook event `type`
    attr_reader :event_type

    # @param event_type [String]
    def initialize(event_type)
      @event_type = event_type
      super("Unknown webhook event type: #{event_type.inspect}. It is not in the openapi event " \
            "catalog (generated/events). If Dinie added a new event type, the SDK must be updated " \
            "from the contract before it can deserialize this payload.")
    end
  end

  # Parse a `Retry-After` value to **seconds**, capped at 60 (architecture §7/§10).
  #
  # Precedence mirrors the retry loop: a `Retry-After-Ms` value (milliseconds) wins, then
  # `Retry-After` as delta-seconds, then `Retry-After` as an HTTP-date (delta from now).
  # Each argument accepts a String or an Array (the first element is used, for repeated
  # headers). A past HTTP-date clamps to 0; an abusive value clamps to 60. Returns the wait
  # in seconds (Float) or `nil` when nothing parseable was given.
  #
  # Public runtime helper, consumed by the transport's retry loop (story 003) and usable in
  # custom post-`RateLimitError` logic.
  #
  # @param retry_after [String, Array<String>, nil] the `Retry-After` header value
  # @param retry_after_ms [String, Array<String>, nil] the `Retry-After-Ms` header value
  # @return [Float, nil] seconds to wait (0..60), or nil
  def self.parse_retry_after(retry_after = nil, retry_after_ms: nil)
    seconds = retry_after_ms_seconds(retry_after_ms) || retry_after_seconds(retry_after)
    return nil if seconds.nil?

    seconds.clamp(0.0, RETRY_AFTER_CAP_SECONDS.to_f)
  end

  # Maximum honored `Retry-After`, in seconds (architecture §10 — verbatim from the V0.2 freeze).
  RETRY_AFTER_CAP_SECONDS = 60

  # @api private
  def self.retry_after_ms_seconds(value)
    raw = first_header_value(value)
    return nil if raw.nil?

    ms = Float(raw, exception: false)
    ms.nil? ? nil : ms / 1000.0
  end

  # @api private
  def self.retry_after_seconds(value)
    raw = first_header_value(value)&.strip
    return nil if raw.nil? || raw.empty?

    seconds = Float(raw, exception: false)
    return seconds if seconds

    http_date_delta(raw)
  end

  # @api private
  def self.http_date_delta(raw)
    Time.httpdate(raw) - Time.now
  rescue ArgumentError
    nil
  end

  # @api private
  def self.first_header_value(value)
    raw = value.is_a?(Array) ? value.first : value
    raw&.to_s
  end

  private_class_method :retry_after_ms_seconds, :retry_after_seconds, :http_date_delta, :first_header_value

  module Internal
    # The transport-agnostic error dispatcher. Builds the right {Dinie::APIError} from an
    # HTTP error response and reads the RFC 9457 Problem Details body.
    #
    # This is the controlled runtime → generated seam (architecture §4): it references the
    # **generated** constant {Dinie::Internal::ERROR_REGISTRY} (defined in
    # `generated/errors/registry.rb`). The reference is the forcing-function — if the error
    # surface changes without regenerating the table, dispatch specs break. The runtime
    # never `require`s the generated layer; the barrel loads the registry before any call.
    module Errors
      # Header carrying the per-request correlation id, surfaced as `error.request_id`.
      REQUEST_ID_HEADER = "x-request-id"

      module_function

      # Build the typed error for an HTTP error response: dispatch by Problem Details `type`
      # URL, then by HTTP status, then by the ≥500 band fallback. The body is parsed as JSON
      # once (symbol keys); a non-JSON body is preserved as raw text.
      #
      # @param status [Integer] HTTP status code
      # @param headers [Hash] response headers
      # @param body [String, nil] raw response body
      # @param force [Class, nil] when given, skip dispatch and build this exact class
      #   (used by the transport to guarantee an `AuthError` on a persistent 401)
      # @return [Dinie::APIStatusError]
      def from_response(status:, headers: {}, body: nil, force: nil)
        record = parse_problem(body)
        type_url = string_value(record, :type)
        request_id = header_request_id(headers) || string_value(record, :request_id)
        ctor = force || dispatch(type_url, status)
        ctor.new(status: status, body: record || presentable_body(body), headers: headers || {},
                 request_id: request_id)
      end

      # @api private
      def dispatch(type_url, status)
        registry = Dinie::Internal::ERROR_REGISTRY
        (type_url && registry[:by_type][type_url]) ||
          registry[:by_status][status] ||
          fallback_ctor(status)
      end

      # @api private
      def fallback_ctor(status)
        return Dinie::Internal::ERROR_REGISTRY[:fallback_5xx] if status >= 500

        Dinie::APIStatusError
      end

      # @api private
      def parse_problem(body)
        return nil unless body.is_a?(String) && !body.empty?

        parsed = JSON.parse(body, symbolize_names: true)
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end

      # @api private
      def presentable_body(body)
        body.is_a?(String) && !body.empty? ? body : nil
      end

      # @api private
      def header_request_id(headers)
        value = header_lookup(headers, REQUEST_ID_HEADER)
        value.is_a?(Array) ? value.first : value
      end

      # @api private
      def header_lookup(headers, name)
        return nil unless headers.respond_to?(:each)

        target = name.downcase
        headers.each { |key, value| return value if key.to_s.downcase == target }
        nil
      end

      # @api private
      def string_value(record, key)
        return nil unless record

        value = record[key]
        value.is_a?(String) ? value : nil
      end
    end
  end
end

# frozen_string_literal: true

module Dinie
  module Internal
    # Normalized per-call options, the trailing `request_options:` Hash every public method
    # accepts (architecture §12, RB5). Validates types up front and freezes; the actual
    # header merge against the client defaults (where a `nil` value removes a default) and
    # the timeout/retry wiring happen in the transport (story 003).
    #
    # @example
    #   Dinie::Internal::RequestOptions.coerce(timeout: 5, headers: { "x-trace" => "abc" })
    class RequestOptions
      # @return [Numeric, nil] per-call timeout, in seconds
      attr_reader :timeout
      # @return [String, nil] explicit idempotency key (overrides the auto-generated one)
      attr_reader :idempotency_key
      # @return [Hash{String => String, nil}, nil] per-call header overrides (a `nil` value removes a default)
      attr_reader :headers
      # @return [Integer, nil] per-call retry budget override
      attr_reader :max_retries

      # Coerce a value into a {RequestOptions}: pass an instance through, or build one from a
      # Hash (string or symbol keys; `nil` → empty).
      #
      # @param value [RequestOptions, Hash, nil]
      # @return [RequestOptions]
      # @raise [ArgumentError] on an unknown key or an invalid value type
      def self.coerce(value)
        return value if value.is_a?(self)

        new(**(value || {}).transform_keys(&:to_sym))
      end

      # @param timeout [Numeric, nil] seconds; must be a non-negative Numeric
      # @param idempotency_key [String, nil]
      # @param headers [Hash, nil] values must be String or nil
      # @param max_retries [Integer, nil] must be a non-negative Integer
      # @raise [ArgumentError] on an invalid value type
      def initialize(timeout: nil, idempotency_key: nil, headers: nil, max_retries: nil)
        @timeout = validate_timeout(timeout)
        @idempotency_key = validate_string(idempotency_key, :idempotency_key)
        @headers = validate_headers(headers)
        @max_retries = validate_max_retries(max_retries)
        freeze
      end

      # @return [Hash{Symbol => Object}] the normalized options
      def to_h
        { timeout: timeout, idempotency_key: idempotency_key, headers: headers, max_retries: max_retries }
      end
      alias to_hash to_h

      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(RequestOptions) && other.to_h == to_h
      end
      alias eql? ==

      # @return [Integer]
      def hash
        to_h.hash
      end

      private

      def validate_timeout(value)
        return nil if value.nil?
        unless value.is_a?(Numeric) && !value.negative?
          raise ArgumentError,
                "request_options[:timeout] must be a non-negative Numeric (seconds), got #{value.inspect}"
        end

        value
      end

      def validate_max_retries(value)
        return nil if value.nil?
        unless value.is_a?(Integer) && !value.negative?
          raise ArgumentError, "request_options[:max_retries] must be a non-negative Integer, got #{value.inspect}"
        end

        value
      end

      def validate_string(value, key)
        return nil if value.nil?
        unless value.is_a?(String)
          raise ArgumentError,
                "request_options[:#{key}] must be a String, got #{value.inspect}"
        end

        value
      end

      def validate_headers(value)
        return nil if value.nil?
        raise ArgumentError, "request_options[:headers] must be a Hash, got #{value.inspect}" unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, header_value), acc|
          unless header_value.nil? || header_value.is_a?(String)
            raise ArgumentError,
                  "request_options[:headers] values must be String or nil (nil removes a default), " \
                  "got #{header_value.inspect} for #{key.inspect}"
          end

          acc[key.to_s] = header_value
        end
      end
    end
  end
end

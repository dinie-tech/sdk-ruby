# frozen_string_literal: true

require "time"

module Dinie
  # The rate-limit snapshot read from the most recent response's `X-RateLimit-*` headers
  # (architecture §10, RB6). Surfaced as `client.rate_limit`; `nil` until a response carries
  # valid headers.
  #
  # `reset_at` is the SDK's **only** `Time` (RB6): every body timestamp stays an `Integer`
  # epoch, but this value comes from a transport header (not the wire body), so it is
  # normalized to a `Time` — mirroring the `Date` the TypeScript SDK exposes here.
  #
  # @example
  #   rl = client.rate_limit
  #   rl.remaining        # => 87
  #   rl.reset_at         # => 2026-06-02 12:00:30 UTC
  class RateLimit
    # @return [Integer] ceiling for the current window (`X-RateLimit-Limit`)
    attr_reader :limit
    # @return [Integer] requests left in the current window (`X-RateLimit-Remaining`)
    attr_reader :remaining
    # @return [Time] when the window resets (`X-RateLimit-Reset`)
    attr_reader :reset_at

    # @param limit [Integer]
    # @param remaining [Integer]
    # @param reset_at [Time]
    def initialize(limit:, remaining:, reset_at:)
      @limit = limit
      @remaining = remaining
      @reset_at = reset_at
      freeze
    end

    # @return [Hash{Symbol => Object}]
    def to_h
      { limit: limit, remaining: remaining, reset_at: reset_at }
    end
    alias to_hash to_h

    # Enable pattern matching (`case rl; in { remaining: 0 }`).
    #
    # @param _keys [Array<Symbol>, nil]
    # @return [Hash{Symbol => Object}]
    def deconstruct_keys(_keys) = to_h

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(RateLimit) && other.to_h == to_h
    end
    alias eql? ==

    # @return [Integer]
    def hash
      to_h.hash
    end
  end

  module Internal
    # Parses the three `X-RateLimit-*` headers off the latest response and holds the most
    # recent {Dinie::RateLimit} snapshot for {HttpClient} (architecture §10). Mirrors
    # `sdk-js` `rate-limit.ts` (`parseRateLimit` + `RateLimitTracker`).
    #
    # **All-or-nothing (decision):** {Dinie::RateLimit} has non-nullable fields, so {parse}
    # returns the whole object or `nil` — never a partial. A missing/garbage header makes the
    # parse `nil`, and {#update} then keeps the previous snapshot rather than clobbering a good
    # value with a header-less response (such as the token call).
    class RateLimitTracker
      LIMIT_HEADER = "x-ratelimit-limit"
      REMAINING_HEADER = "x-ratelimit-remaining"
      RESET_HEADER = "x-ratelimit-reset"

      # `X-RateLimit-Reset` values at or above this (seconds) are read as an absolute Unix
      # epoch; anything below as a delta in seconds from now. `1e9` seconds is ~2001-09 — far
      # above any plausible "seconds until reset" window yet below every real epoch.
      EPOCH_THRESHOLD_SECONDS = 1_000_000_000

      # @return [Dinie::RateLimit, nil] latest snapshot, or `nil` before any valid headers
      def snapshot
        @current
      end

      # Fold a response's headers into the snapshot. A header-less or garbage response leaves
      # the previous snapshot untouched (does not reset it to `nil`).
      #
      # @param headers [#each] response headers (case-insensitive keys)
      # @return [void]
      def update(headers)
        parsed = self.class.parse(headers)
        @current = parsed unless parsed.nil?
      end

      # Parse the three `X-RateLimit-*` headers into a {Dinie::RateLimit}, or `nil` when any is
      # absent or unparseable. Never raises.
      #
      # @param headers [#each] response headers
      # @return [Dinie::RateLimit, nil]
      def self.parse(headers)
        limit = parse_count(header_value(headers, LIMIT_HEADER))
        remaining = parse_count(header_value(headers, REMAINING_HEADER))
        reset_at = parse_reset(header_value(headers, RESET_HEADER))
        return nil if limit.nil? || remaining.nil? || reset_at.nil?

        Dinie::RateLimit.new(limit: limit, remaining: remaining, reset_at: reset_at)
      end

      # @api private
      # @return [Integer, nil]
      def self.parse_count(raw)
        return nil if raw.nil?

        value = Integer(raw.to_s.strip, exception: false)
        value && value >= 0 ? value : nil
      end

      # @api private
      # @return [Time, nil]
      def self.parse_reset(raw)
        return nil if raw.nil?

        seconds = Float(raw.to_s.strip, exception: false)
        return nil if seconds.nil? || seconds.negative?

        seconds >= EPOCH_THRESHOLD_SECONDS ? Time.at(seconds) : Time.now + seconds
      end

      # @api private
      # Case-insensitive header lookup; first value of a repeated header.
      # @return [String, nil]
      def self.header_value(headers, name)
        return nil unless headers.respond_to?(:each)

        target = name.downcase
        headers.each do |key, value|
          next unless key.to_s.downcase == target

          return value.is_a?(Array) ? value.first : value
        end
        nil
      end

      private_class_method :parse_count, :parse_reset, :header_value
    end
  end
end

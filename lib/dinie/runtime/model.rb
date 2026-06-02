# frozen_string_literal: true

module Dinie
  # `Internal::` holds everything that is NOT part of the frozen public surface: the
  # transport, the token manager, the error registry, the model base, and the `OMIT`
  # sentinel. It is the Ruby equivalent of "not re-exported by the barrel" in `sdk-js`
  # (architecture §3.1). The generated layer (V0.4) emits subclasses of {Model}; the
  # hand-written runtime references `Dinie::Internal::*`.
  module Internal
    # The sentinel for "this optional argument was not provided" (RB5, architecture §6.2).
    #
    # Ruby collapses "absent" and `nil`; `OMIT` recovers the distinction TypeScript keeps
    # via `exactOptionalPropertyTypes`. Request serializers default optional keyword
    # arguments to `OMIT` and drop any key still equal to it, so an omitted field never
    # reaches the wire — while an explicit `nil` is sent as JSON `null` (a required-nullable
    # field). Compare by identity: `value.equal?(Dinie::Internal::OMIT)` or the
    # {Internal.omitted?} helper. There is exactly one instance and it is frozen.
    OMIT = Object.new

    # @return [String]
    def OMIT.inspect = "#<Dinie::Internal::OMIT>"

    # @return [String]
    def OMIT.to_s = inspect

    OMIT.freeze

    # Identity check for the {OMIT} sentinel.
    #
    # @param value [Object] any value
    # @return [Boolean] true only when `value` IS the {OMIT} sentinel
    def self.omitted?(value)
      value.equal?(OMIT)
    end

    # Base class for every generated model (architecture §5.1, RB3/RB18).
    #
    # Gives POROs value-semantics without `Data.define`, so the floor stays at Ruby 3.1
    # (Block 0). A subclass declares its fields with {attribute} in alphabetical order
    # (R-ORDER); the source-emission order is the single source of truth for `to_h` and
    # `inspect`, so the runtime never sorts at call time. Instances are frozen after
    # construction, mirroring the read-only character of the `sdk-js` models.
    #
    # @example
    #   class Customer < Dinie::Internal::Model
    #     attribute :cpf, :id, :name, :status
    #   end
    #
    #   c = Customer.new(cpf: "***", id: "cust_1", name: "Ana", status: "active")
    #   c.id                       # => "cust_1"
    #   c.to_h                     # => {cpf: "***", id: "cust_1", name: "Ana", status: "active"}
    #   c == Customer.new(...)     # value-equality by attributes
    #   case c; in {status:}; end  # pattern matching via deconstruct_keys
    class Model
      # PII attribute names redacted by {#inspect}. Kept in sync with the logger's body
      # redaction list (architecture §9 / story 005, which owns the canonical set).
      REDACTED_ATTRIBUTES = %i[
        access_token account client_secret cnpj cpf cvv password phone secret
      ].freeze

      class << self
        # The declared attribute names, in declaration (R-ORDER) order. Subclasses inherit
        # and may extend their parent's list.
        #
        # @return [Array<Symbol>]
        def attributes
          @attributes ||= []
        end

        # Declare one or more attributes: defines an `attr_reader` for each and appends it
        # to {attributes} in declaration order. Idempotent per name.
        #
        # @param names [Array<Symbol, String>] attribute names, alphabetical (R-ORDER)
        # @return [void]
        def attribute(*names)
          names.each do |name|
            sym = name.to_sym
            next if attributes.include?(sym)

            attributes << sym
            attr_reader(sym)
          end
        end

        # Carry the parent's attribute list into each subclass.
        #
        # @param subclass [Class]
        # @return [void]
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@attributes, attributes.dup)
        end
      end

      # Build a frozen instance from keyword arguments — one per declared attribute.
      #
      # Every declared attribute is required (hydration always passes a value, `nil`
      # included), and unknown keywords are rejected, so a contract drift surfaces loudly
      # instead of silently dropping data.
      #
      # @param attrs [Hash{Symbol => Object}] one value per declared attribute
      # @raise [ArgumentError] when a declared attribute is missing or an unknown one is given
      def initialize(**attrs)
        expected = self.class.attributes
        validate_keys!(expected, attrs)
        expected.each { |name| instance_variable_set(:"@#{name}", attrs[name]) }
        freeze
      end

      # @return [Hash{Symbol => Object}] attributes in declaration (R-ORDER) order — deterministic
      def to_h
        self.class.attributes.to_h { |name| [name, public_send(name)] }
      end
      alias to_hash to_h

      # Enable pattern matching (`case model; in {status: "active"}`).
      #
      # @param _keys [Array<Symbol>, nil] requested keys (ignored — the full hash matches)
      # @return [Hash{Symbol => Object}]
      def deconstruct_keys(_keys) = to_h

      # Value-equality: same class and same attribute values.
      #
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.class == self.class && other.to_h == to_h
      end
      alias eql? ==

      # @return [Integer] consistent with {eql?} so instances work as Hash keys
      def hash
        [self.class, to_h].hash
      end

      # Like {to_h}, but with PII redacted — safe for logs and the console.
      #
      # @return [String]
      def inspect
        pairs = self.class.attributes.map do |name|
          rendered = REDACTED_ATTRIBUTES.include?(name) ? "[REDACTED]" : public_send(name).inspect
          "#{name}=#{rendered}"
        end
        "#<#{self.class.name} #{pairs.join(", ")}>"
      end

      private

      def validate_keys!(expected, attrs)
        missing = expected - attrs.keys
        unless missing.empty?
          raise ArgumentError, "missing keyword#{"s" if missing.size > 1}: #{missing.map(&:inspect).join(", ")}"
        end

        extra = attrs.keys - expected
        return if extra.empty?

        raise ArgumentError, "unknown keyword#{"s" if extra.size > 1}: #{extra.map(&:inspect).join(", ")}"
      end
    end
  end
end

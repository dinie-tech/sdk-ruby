# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "kyc"

# `Customer` + the **hydrate/dump convention every resource/event story (007–011) copies**
# (architecture §6, §3.3). Hand-authored in V0.3 to mirror what the V0.5 generator will emit
# from `components.schemas.Customer` / `CreateCustomerRequest` / `UpdateCustomerRequest`
# (`openapi.yaml @ 3fcfd83`, the frozen-surface SoT). THIS FILE IS THE EXEMPLAR — keep it
# crisp; downstream types reproduce its exact shape.
#
# ── The convention (Ruby): snake-native, zero casing conversion (RB2) ──
# The wire is `snake_case` and so is the Ruby surface, so — unlike the TS port — there is NO
# `*Wire` type and NO casing (de)serializer. The (de)serializers still exist, with different
# work:
#
#   * hydrate → `self.deserialize(raw)`: a symbol-keyed wire Hash (from
#     `JSON.parse(symbolize_names: true)`) becomes a typed, frozen PORO. It constructs the
#     object graph explicitly (recursing into sub-objects), never a blind symbolize/slice.
#   * dump → `self.serialize_<op>(**fields)`: idiomatic kwargs (RB4) become the wire Hash,
#     dropping `Internal::OMIT` keys. Read-only models have NO dump.
#
# Which methods a type gets: a read model gets a `deserialize`; a request body gets a
# `serialize_*`. `Customer` is a read model AND has two request bodies, so it carries all
# three. `CreditOffer` is read-only (deserialize only — R10).
#
# ── The four rules every (de)serializer obeys (feeds principles.md / comparison.md, 014) ──
#   R-EXPLICIT  Field-by-field, never reflective. Each attribute is named in `deserialize` and
#               each key in `serialize_*`, so the diff is reviewable and a contract drift
#               raises an ArgumentError from the base initializer (the completeness
#               forcing-function) instead of silently dropping data.
#   R-ORDER     Keys are alphabetical by target name. For models this IS the `attribute`
#               declaration order (which `to_h` inherits); for dumps it is the literal key
#               order. Stable ordering keeps the V0.5 generator diff minimal.
#   R-OPTIONAL  On dump, an omitted optional defaults to `Internal::OMIT` and is dropped; an
#               explicit `nil` is kept and sent as JSON `null` (required-nullable). This
#               recovers the absent-vs-null distinction TS keeps via
#               `exactOptionalPropertyTypes`. On hydrate, an absent optional simply arrives as
#               `nil` (Ruby collapses absent/null on reads — OMIT is a dump-side concern).
#   R-EPOCH     Epoch timestamps stay `Integer`, NEVER `Time` (lossy, non-deterministic). The
#               sole `Time` in the SDK is `RateLimit#reset_at` (a transport header).
#
# ── Field map (`components.schemas.Customer` @ 3fcfd83) — wire snake = surface snake ──
#   cnpj          → String | nil   (required, nullable; formatted XX.XXX.XXX/XXXX-XX)
#   cpf           → String         (formatted XXX.XXX.XXX-XX in responses)
#   created_at    → Integer        (epoch seconds, R-EPOCH)
#   email         → String
#   external_id   → String | nil   (required, nullable)
#   id            → CustomerId     (`cust_…`, NOT `cus_` — architecture R2)
#   kyc           → Array<Kyc::*Requirement> | nil  (optional; hydrated through the discriminated
#                                  `Dinie::Kyc.deserialize_requirement` — story 009)
#   name          → String | nil   (required, nullable)
#   phone         → String         (E.164)
#   status        → String         (CustomerStatus enum)
#   trading_name  → String | nil   (required, nullable)
#   updated_at    → Integer        (epoch seconds, R-EPOCH)
#
# ── Demo ≠ contract (architecture §19) ──
# The version spec's `customers.create(tax_id:)` does NOT exist: the real create body is
# `{ email, phone, cpf, cnpj, name?, external_id? }` (R1). There is no `tax_id`.
module Dinie
  # A Dinie customer (`cust_…`) — the full read model returned by the customers resource.
  class Customer < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :cnpj, :cpf, :created_at, :email, :external_id, :id,
              :kyc, :name, :phone, :status, :trading_name, :updated_at

    # Hydrate a wire customer (symbol-keyed Hash) into a {Customer}. Explicit per-field
    # (R-EXPLICIT); epoch fields stay `Integer` (R-EPOCH); the required-nullable fields
    # (`cnpj`/`name`/`external_id`/`trading_name`) are carried as `String | nil`. `kyc` is the
    # one optional field — absent during `creating`, so it arrives as `nil`.
    #
    # `kyc` recurses into the discriminated KYC requirement union (story 009): each entry hydrates
    # to a concrete `Dinie::Kyc::*Requirement` via {Dinie::Kyc.deserialize_requirement}, dispatched
    # by `requirement_type`. `nil` (absent) and `[]` (none yet) both pass through cleanly.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [Customer]
    def self.deserialize(raw)
      new(
        cnpj: raw[:cnpj],
        cpf: raw[:cpf],
        created_at: raw[:created_at],
        email: raw[:email],
        external_id: raw[:external_id],
        id: raw[:id],
        kyc: raw[:kyc]&.map { |requirement| Dinie::Kyc.deserialize_requirement(requirement) },
        name: raw[:name],
        phone: raw[:phone],
        status: raw[:status],
        trading_name: raw[:trading_name],
        updated_at: raw[:updated_at]
      )
    end

    # Dump a `CreateCustomerRequest` wire body from idiomatic kwargs (RB4). The four required
    # fields are always present; `name`/`external_id` default to `Internal::OMIT` and are
    # dropped when omitted (R-OPTIONAL). Keys alphabetical (R-ORDER).
    #
    # @param email [String] required
    # @param phone [String] required, E.164
    # @param cpf [String] required
    # @param cnpj [String] required
    # @param name [String, Internal::OMIT] optional display name
    # @param external_id [String, Internal::OMIT] optional partner reference
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_create(email:, phone:, cpf:, cnpj:, name: Internal::OMIT, external_id: Internal::OMIT)
      { cnpj:, cpf:, email:, external_id:, name:, phone: }
        .reject { |_key, value| Internal.omitted?(value) }
    end

    # Dump an `UpdateCustomerRequest` PATCH wire body. Every field is optional; only the keys
    # the caller set (not `Internal::OMIT`) are emitted (R-OPTIONAL). Keys alphabetical.
    #
    # @param email [String, Internal::OMIT] new contact email
    # @param phone [String, Internal::OMIT] new contact phone, E.164
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_update(email: Internal::OMIT, phone: Internal::OMIT)
      { email:, phone: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end
end

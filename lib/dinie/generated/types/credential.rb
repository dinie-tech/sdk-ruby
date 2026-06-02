# frozen_string_literal: true

require_relative "../../runtime/model"

# `Credential` types — the API-key management family (architecture §3.3, §6). Hand-authored
# in V0.3 to mirror future generator output; `components.schemas.Credential` /
# `CredentialWithSecret` / `CreateCredentialRequest` (`openapi.yaml @ 3fcfd83`) are the SoT.
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar).
#
# ── allOf → subclass (the deterministic mapping of `allOf`) ──
# The contract defines `CredentialWithSecret` as `allOf: [Credential, { client_secret }]`. The
# Ruby mapping of an `allOf` extension is subclassing: {CredentialWithSecret} < {Credential}
# inherits the base attributes (their R-ORDER preserved) and appends the creation-only
# `client_secret`. The (de)serializers still list every field explicitly (R-EXPLICIT) — the
# subclass removes duplication in the *type*, not in the mapping. Because `deserialize` calls
# `new` with the full attribute set, the subclass MUST override it (the base's 8-key `new`
# would raise on the 9-attribute subclass — the completeness forcing-function at work).
#
# ── Secret-bearing response ──
# {CredentialWithSecret} carries `client_secret` and is returned ONLY by `credentials.create`
# (shown exactly once). The `list`-returned {Credential} has no secret. `client_secret` is on
# the {Dinie::Internal::Model} PII-redaction list, so even a debug-logged creation response
# keeps the secret out of the logs.
#
# ── Field map (`components.schemas.Credential` @ 3fcfd83) ──
#   client_id     → ApiClientId    (`dinie_ci_…`)
#   created_at    → Integer        (epoch seconds, R-EPOCH)
#   expires_at    → Integer | nil  (required, nullable)
#   id            → ApiClientId
#   last_used_at  → Integer | nil  (required, nullable)
#   name          → String
#   status        → String         (CredentialStatus enum)
#   updated_at    → Integer        (epoch seconds, R-EPOCH)
#   client_secret → String         ({CredentialWithSecret} only)
#
# `CreateCredentialRequest`: `name` (required) + `expires_at` (OPTIONAL and nullable): omit to
# default to "never expires", pass an Integer to pin an expiry, or pass `nil` explicitly for
# never — so the serializer omits only on `OMIT` and sends an explicit `nil` as JSON `null`.
module Dinie
  # An API credential (`dinie_ci_…`) — the read model returned by `list` (NO secret).
  class Credential < Internal::Model
    # R-ORDER: alphabetical declaration order (== `to_h` order).
    attribute :client_id, :created_at, :expires_at, :id, :last_used_at, :name, :status, :updated_at

    # Hydrate a wire credential (symbol-keyed Hash) into a {Credential}. Explicit per-field
    # (R-EXPLICIT); `expires_at`/`last_used_at` are required-but-nullable (always present,
    # carried as `Integer | nil`); epoch fields stay `Integer` (R-EPOCH).
    #
    # @param raw [Hash{Symbol => Object}]
    # @return [Credential]
    def self.deserialize(raw)
      new(
        client_id: raw[:client_id],
        created_at: raw[:created_at],
        expires_at: raw[:expires_at],
        id: raw[:id],
        last_used_at: raw[:last_used_at],
        name: raw[:name],
        status: raw[:status],
        updated_at: raw[:updated_at]
      )
    end

    # Dump a `CreateCredentialRequest` wire body from idiomatic kwargs (RB4). Required `name`
    # is always present; `expires_at` defaults to `Internal::OMIT` and is dropped only when
    # omitted — an explicit `nil` IS sent (JSON `null` = "never expires"). Keys alphabetical
    # (R-ORDER); `OMIT` keys removed (R-OPTIONAL).
    #
    # @param name [String] human-readable label (required)
    # @param expires_at [Integer, nil, Internal::OMIT] expiry epoch seconds; `nil` = never
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_create(name:, expires_at: Internal::OMIT)
      { expires_at:, name: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end

  # The creation-only credential — {Credential} plus the `client_secret` shown exactly once
  # (the contract's `allOf`). Returned by `credentials.create`; never by `list`.
  class CredentialWithSecret < Credential
    # Appends the creation-only field to the inherited base attributes (allOf extension).
    attribute :client_secret

    # Hydrate the creation response into a {CredentialWithSecret}. Lists every field
    # explicitly (R-EXPLICIT) — the subclass removes duplication in the type, not the mapping;
    # `client_secret` is the creation-only field absent from {Credential}.
    #
    # @param raw [Hash{Symbol => Object}]
    # @return [CredentialWithSecret]
    def self.deserialize(raw)
      new(
        client_id: raw[:client_id],
        client_secret: raw[:client_secret],
        created_at: raw[:created_at],
        expires_at: raw[:expires_at],
        id: raw[:id],
        last_used_at: raw[:last_used_at],
        name: raw[:name],
        status: raw[:status],
        updated_at: raw[:updated_at]
      )
    end
  end
end

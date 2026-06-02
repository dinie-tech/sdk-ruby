# frozen_string_literal: true

require_relative "../../runtime/model"

# `WebhookEndpoint` types — REST MANAGEMENT of webhook endpoints (architecture §3.2, §3.3, §6).
# Hand-authored in V0.3 to mirror future generator output; the SoT is
# `components.schemas.WebhookEndpoint` / `WebhookEndpointWithSecret` / `WebhookSecretRotation` /
# `CreateWebhookEndpointRequest` / `UpdateWebhookEndpointRequest` (`openapi.yaml @ 3fcfd83`).
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar). Ports `sdk-js`
# `src/generated/types/webhook-endpoint.ts`.
#
# ── NOT the webhook RUNTIME ──
# This file is the management surface for `client.webhook_endpoints` (create/list/retrieve/update/
# delete/rotate_secret). It is DISTINCT from webhook event RECEPTION — `Dinie::Webhooks.extract`
# and the `Events::*` union live in `runtime/webhooks.rb` + `generated/events/` (story 011). A
# {WebhookEndpoint} is the configuration record; an `Events::*` is a delivered notification.
#
# ── allOf → subclass (the deterministic mapping of `allOf`) ──
# The contract defines `WebhookEndpointWithSecret` as `allOf: [WebhookEndpoint, { secret }]`. The
# Ruby mapping of an `allOf` extension is subclassing: {WebhookEndpointWithSecret} <
# {WebhookEndpoint} inherits the base attributes (their R-ORDER preserved) and appends the
# creation-only `secret`. The (de)serializers still list every field explicitly (R-EXPLICIT) — the
# subclass removes duplication in the *type*, not in the mapping. Because `deserialize` calls `new`
# with the full attribute set, the subclass MUST override it (the base's 7-key `new` would raise
# on the 8-attribute subclass — the completeness forcing-function at work).
#
# ── Secret-bearing responses ──
# {WebhookEndpointWithSecret} (returned ONLY by `create`) and {WebhookSecretRotation} (returned
# ONLY by `rotate_secret`) carry the HMAC signing `secret` (`whsec_…`) shown exactly once. The
# `list`/`retrieve`/`update`-returned {WebhookEndpoint} has NO secret. `secret` is on the
# {Dinie::Internal::Model} PII-redaction list, so even a debug-logged response keeps it out of the
# logs.
#
# ── Field map (`components.schemas.WebhookEndpoint` @ 3fcfd83 — all required) ──
#   created_at   → Integer   (epoch seconds, R-EPOCH)
#   description  → String
#   events       → Array<String>   (subscribed types; `*` wildcards)
#   id           → WebhookEndpointId   (`we_…`)
#   status       → String     (WebhookEndpointStatus enum: `active` | `disabled`)
#   updated_at   → Integer    (epoch seconds, R-EPOCH)
#   url          → String     (HTTPS delivery URL)
#   secret       → String     ({WebhookEndpointWithSecret} only)
#
# `CreateWebhookEndpointRequest`: `url` (required) + `events` / `description` (OPTIONAL → omit on
# {Internal::OMIT}). `UpdateWebhookEndpointRequest`: every field optional (PATCH subset) — `url`,
# `events`, `description`, `status`. `WebhookSecretRotation`: `{ id, secret,
# previous_secret_expires_at }` (all required; the expiry is an epoch-second `Integer`, R-EPOCH).
module Dinie
  # A configured webhook endpoint (`we_…`) — the read model returned by `list`/`retrieve`/`update`
  # (NO secret).
  class WebhookEndpoint < Internal::Model
    # R-ORDER: alphabetical declaration order (== `to_h` order).
    attribute :created_at, :description, :events, :id, :status, :updated_at, :url

    # Hydrate a wire endpoint (symbol-keyed Hash) into a {WebhookEndpoint}. Explicit per-field
    # (R-EXPLICIT); epoch fields stay `Integer` (R-EPOCH); `events` is copied as-is (array of
    # strings). Every field is required.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [WebhookEndpoint]
    def self.deserialize(raw)
      new(
        created_at: raw[:created_at],
        description: raw[:description],
        events: raw[:events],
        id: raw[:id],
        status: raw[:status],
        updated_at: raw[:updated_at],
        url: raw[:url]
      )
    end

    # Dump a `CreateWebhookEndpointRequest` wire body from idiomatic kwargs (RB4). Required `url`
    # is always present; `events` / `description` default to {Internal::OMIT} and are dropped when
    # omitted (R-OPTIONAL). Keys alphabetical (R-ORDER).
    #
    # @param url [String] HTTPS URL to receive webhook deliveries (required)
    # @param events [Array<String>, Internal::OMIT] event types to subscribe to (`*` wildcards)
    # @param description [String, Internal::OMIT] human-readable description
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_create(url:, events: Internal::OMIT, description: Internal::OMIT)
      { description:, events:, url: }.reject { |_key, value| Internal.omitted?(value) }
    end

    # Dump an `UpdateWebhookEndpointRequest` wire body (PATCH subset) from idiomatic kwargs (RB4).
    # Every field is optional; only the keys the caller set are emitted (R-OPTIONAL). Keys
    # alphabetical (R-ORDER).
    #
    # @param url [String, Internal::OMIT] new HTTPS delivery URL
    # @param events [Array<String>, Internal::OMIT] new subscribed event types (`*` wildcards)
    # @param description [String, Internal::OMIT] new human-readable description
    # @param status [String, Internal::OMIT] `active` to enable / `disabled` to disable
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_update(url: Internal::OMIT, events: Internal::OMIT, description: Internal::OMIT,
                              status: Internal::OMIT)
      { description:, events:, status:, url: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end

  # The creation-only endpoint — {WebhookEndpoint} plus the `secret` shown exactly once (the
  # contract's `allOf`). Returned by `webhook_endpoints.create`; never by `list`/`retrieve`.
  class WebhookEndpointWithSecret < WebhookEndpoint
    # Appends the creation-only field to the inherited base attributes (allOf extension).
    attribute :secret

    # Hydrate the creation response into a {WebhookEndpointWithSecret}. Lists every field
    # explicitly (R-EXPLICIT) — the subclass removes duplication in the type, not the mapping;
    # `secret` is the creation-only field absent from {WebhookEndpoint}.
    #
    # @param raw [Hash{Symbol => Object}]
    # @return [WebhookEndpointWithSecret]
    def self.deserialize(raw)
      new(
        created_at: raw[:created_at],
        description: raw[:description],
        events: raw[:events],
        id: raw[:id],
        secret: raw[:secret],
        status: raw[:status],
        updated_at: raw[:updated_at],
        url: raw[:url]
      )
    end
  end

  # The result of `webhook_endpoints.rotate_secret` — the new signing secret plus the old secret's
  # grace deadline. Returned ONLY by `rotate_secret`. Carries `secret`, redacted in `inspect`.
  class WebhookSecretRotation < Internal::Model
    # R-ORDER: alphabetical declaration order (== `to_h` order).
    attribute :id, :previous_secret_expires_at, :secret

    # Hydrate a wire rotation response into a {WebhookSecretRotation}. Explicit per-field
    # (R-EXPLICIT); `previous_secret_expires_at` stays `Integer` (R-EPOCH). Every field required.
    #
    # @param raw [Hash{Symbol => Object}]
    # @return [WebhookSecretRotation]
    def self.deserialize(raw)
      new(
        id: raw[:id],
        previous_secret_expires_at: raw[:previous_secret_expires_at],
        secret: raw[:secret]
      )
    end

    # Dump the `rotate-secret` wire body from idiomatic kwargs (RB4). The sole field
    # `expire_current_in` (seconds the old secret stays valid; server default 3600, max 86400) is
    # OPTIONAL and dropped on {Internal::OMIT} (R-OPTIONAL) — an empty body lets the server apply
    # its default grace period.
    #
    # @param expire_current_in [Integer, Internal::OMIT] grace seconds for the previous secret
    # @return [Hash{Symbol => Object}] the wire request body
    def self.serialize_rotate_secret(expire_current_in: Internal::OMIT)
      { expire_current_in: }.reject { |_key, value| Internal.omitted?(value) }
    end
  end
end

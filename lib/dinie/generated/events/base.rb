# frozen_string_literal: true

require_relative "../../runtime/model"

# `Dinie::Events::WebhookEventBase` — the common webhook ENVELOPE shared by all 15 events
# (architecture §3.1, §8; frozen surface "15 webhook events / 11 schemas"). Hand-authored in V0.3
# to mirror future generator output; `components.schemas.WebhookEventBase` (`openapi.yaml @
# 3fcfd83`) is the SoT. Ports `sdk-js` `src/generated/events/base.ts` (@ `19c9bca`).
#
# ── Envelope field map (`components.schemas.WebhookEventBase` @ 3fcfd83) — wire snake = surface snake ──
#   api_version   → String   (e.g. `2026-03-01`)
#   created_at    → Integer  (epoch seconds, R-EPOCH)
#   data          → <event-specific>  (a typed `*Data` model, narrowed per member)
#   delivery_id   → String   (`dlv_…`, plain string — no contract pattern)
#   id            → EventId  (`evt_…`, plain String)
#   timestamp     → Integer  (epoch seconds, R-EPOCH)
#   type          → String   (the discriminant; pinned to a literal per member)
#
# ── Why a shared base class (DS-EVENT envelope) ──
# Every event schema is an openapi `allOf: [WebhookEventBase, {type, data}]`. The base declares the
# seven envelope attributes ONCE (R-ORDER alphabetical); `Internal::Model.inherited` copies the
# attribute list into each of the 15 event subclasses, so a member only defines its `deserialize`
# (envelope inlined, `data` delegated to its `*Data` model). `createdAt`/`timestamp` are integer
# epoch seconds (R-EPOCH), NEVER `Time`. `delivery_id` has no `*Id` schema (no pattern), so it is a
# plain `String`. Never instantiated directly — the partner sees only the concrete members.
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Requires the runtime model base (the controlled `generated → runtime`
# import) and nothing else from `runtime/`. The public surface is `Dinie::Events::*`; the
# per-type `deserialize` are the internal hydrate path consumed by `runtime/webhooks.rb` via
# {Dinie::Events::DESERIALIZERS} and by the conformance harness (012).
module Dinie
  # The 15 typed webhook events + the {DESERIALIZERS} dispatch table (architecture §3.1, §4.1, §8).
  # The partner discriminates by CLASS (`case event; when Dinie::Events::CustomerCreated`, §6.3).
  module Events
    # Abstract envelope shared by all 15 events. Declares the seven Standard Webhooks fields
    # (R-ORDER); every concrete member inherits them and pins its own `type` + `data`. Never
    # instantiated directly.
    class WebhookEventBase < Internal::Model
      # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
      attribute :api_version, :created_at, :data, :delivery_id, :id, :timestamp, :type
    end
  end
end

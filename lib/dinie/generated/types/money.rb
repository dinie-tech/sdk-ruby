# frozen_string_literal: true

# `Money` — the shared monetary value type (architecture §3.3, deferred decision §21.2).
#
# ── Shape resolution (§21.2) ──
# `components.schemas.Money` (`openapi.yaml @ 3fcfd83`) is `type: number, format: double` (BRL)
# — NOT an `{ amount, currency }` object and NOT an integer of cents. The frozen TS surface
# (`sdk-js @ 19c9bca`) mirrors it as `type Money = number`. The Ruby port follows: `Money` is a
# plain `Float` (the wire value, unchanged) — no wrapper type, no cents/object structure the
# contract does not express. A `Float` round-trips losslessly through `JSON.parse`, and
# treating it as anything else would invent structure (and be lossy).
#
# There is therefore NO `Dinie::Money` runtime class: in Ruby the value IS a `Float`. The type
# lives doc-only in RBS (`type money = Float`, story 013); this file documents the decision and
# gives the V0.5 generator a deterministic per-schema target — it mirrors `money.ts`, which is
# likewise a pure type alias with no runtime construct.
#
# Used by: `CreditOffer#approved_amount` / `#min_amount` (this story) and, later, the
# simulation/loan amount fields (stories 008+).
module Dinie
  # `Money` is a plain `Float` (BRL) — see the file header. No runtime construct exists; the
  # value IS a `Float`. The type is carried doc-only in RBS (`type money = Float`).
end

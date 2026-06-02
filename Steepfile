# frozen_string_literal: true

# Steep configuration for the RBS mirror in `sig/` (architecture §5.2, story 013).
#
# ── §21.3 decision: the `steep check` CI gate is INFORMATIVE (non-blocking) in v1 ──
# The gate runs `continue-on-error: true` in `.github/workflows/ci.yml`. The full public surface
# (the generated types/resources/client/events + the runtime model/errors/page/rate_limit/
# request_options/webhooks/retry/idempotency) type-checks against this `sig/`; stdlib is wired via
# `library`, and Faraday (no bundled RBS, not in `rbs collection` at usable fidelity) is resolved by
# a deliberately loose vendored stub (`sig/_external/faraday.rbs`).
#
# What is left is a small, bounded residual of Steep's static-analysis limitations against
# idiomatic Ruby — NOT type errors in our code, and NOT safe to silence globally (that would hide
# real drift, the anti-pattern the architecture warns against):
#   * `Ruby::InsufficientKeywordArguments` (×5) — the `**fields` / `**upload` splat idiom (RB4): a
#     resource collects keyword args into a rest-hash and re-splats them into a serializer with
#     required kwargs. Steep cannot prove a splat covers required keywords; Ruby validates them at
#     runtime. Removed once the V0.4 generator emits explicit-kwarg resources.
#   * `Ruby::UnannotatedEmptyCollection` / the `[]=`-on-nilable it induces (×4) — `each_with_object({})`
#     memos Steep types as the method's nilable return; fixed by an inline `#:` annotation on the
#     literal (a runtime-source edit, out of scope for this docs/types story).
#   * `Ruby::BlockTypeMismatch` (×1) — `&block` nilability through the overloaded `Page#each`.
#
# Promotion path (→ blocking): annotate the empty-hash memos, emit explicit-kwarg resources, and the
# residual goes to zero. Until then the gate is informative so a regression elsewhere still SHOWS in
# the run output without being masked by a blanket suppression.
#
# stdlib signatures are wired via `library` (they ship with rbs).
target :lib do
  signature "sig"
  check "lib"

  library "json", "time", "logger", "uri", "securerandom", "base64", "openssl", "digest", "stringio"
end

# frozen_string_literal: true

# Curated public barrel — the single entry point consumers load via `require "dinie"`.
#
# It uses explicit `require_relative`s (no Zeitwerk — RB16) so load order is deterministic
# for the generated error/event registries. This mirrors `src/index.ts` in `sdk-js`:
# the runtime is required first (hand-written mechanism), then the generated indexes.
#
# At bootstrap only `version` exists. The runtime and generated layers land in later
# stories; their requires stay as commented TODOs so the smoke suite is green before
# those files exist. Uncomment each line in the story that introduces the file.

require_relative "dinie/version"

# --- runtime (hand-written — CODEOWNER humans — stories 002–005) ---------------
require_relative "dinie/runtime/model"
require_relative "dinie/runtime/errors"
require_relative "dinie/runtime/request_options"
require_relative "dinie/runtime/idempotency"
require_relative "dinie/runtime/rate_limit"
require_relative "dinie/runtime/retry"
require_relative "dinie/runtime/http"
require_relative "dinie/runtime/token_manager"
require_relative "dinie/runtime/logger"
require_relative "dinie/runtime/paginator"
require_relative "dinie/runtime/multipart"
# require_relative "dinie/runtime/webhooks"

# --- generated (hand-authored V0.3 — CODEOWNER bot — stories 006–011) ----------
require_relative "dinie/generated/errors/registry"
require_relative "dinie/generated/types"
# require_relative "dinie/generated/events"
require_relative "dinie/generated/resources"
require_relative "dinie/generated/client"

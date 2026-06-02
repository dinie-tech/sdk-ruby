# frozen_string_literal: true

require_relative "../../runtime/errors"

# Server-response error catalog + dispatch table (RB14, architecture §4.1, §7).
#
# Hand-authored in V0.3 to mirror future generator output; `openapi.yaml @ 3fcfd83` is the
# source of truth. Each marker is an empty subclass of {Dinie::APIStatusError} — the base
# does all body-field extraction (`code`, `request_id`, …), so a marker adds nothing but its
# identity. {Dinie::Internal::ERROR_REGISTRY} is the explicit, deterministic dispatch table
# the runtime consults via {Dinie::Internal::Errors.from_response}: this is the controlled
# runtime → generated seam (no import side-effects, unlike `sdk-js`).
#
# Entries are alphabetical by class so the V0.4 generator produces a minimal diff.
module Dinie
  # 400 — openapi `type` URL `invalid-request`.
  class BadRequestError < APIStatusError; end
  # 401 — openapi `type` URL `authentication-failed`.
  class AuthError < APIStatusError; end
  # 403 — `type` URL `forbidden` is ORPHAN in `openapi.yaml @ 3fcfd83` (P1 debt, story 015).
  # The class stays (V0.2 decision) and dispatches by status until the contract PR lands.
  class PermissionError < APIStatusError; end
  # 404 — openapi `type` URL `not-found`.
  class NotFoundError < APIStatusError; end
  # 409 — openapi `type` URL `conflict`.
  class ConflictError < APIStatusError; end
  # 422 — openapi `type` URL `validation-failed`.
  class ValidationError < APIStatusError; end
  # 429 — openapi `type` URL `rate-limit-exceeded`.
  class RateLimitError < APIStatusError; end
  # 500 (also 503) and the ≥500 band fallback — openapi `type` URL `internal`.
  class ServerError < APIStatusError; end

  module Internal
    # Dispatch table for {Errors.from_response}: by Problem Details `type` URL first, then by
    # HTTP status, then the ≥500 band fallback. All 8 markers are reachable; `PermissionError`
    # has no `by_type` entry because its `forbidden` URL is absent from the contract (P1 debt).
    ERROR_REGISTRY = {
      by_type: {
        "https://docs.dinie.com/errors/invalid-request" => Dinie::BadRequestError,
        "https://docs.dinie.com/errors/authentication-failed" => Dinie::AuthError,
        # "https://docs.dinie.com/errors/forbidden" => Dinie::PermissionError, # P1 debt: orphan type URL
        "https://docs.dinie.com/errors/not-found" => Dinie::NotFoundError,
        "https://docs.dinie.com/errors/conflict" => Dinie::ConflictError,
        "https://docs.dinie.com/errors/validation-failed" => Dinie::ValidationError,
        "https://docs.dinie.com/errors/rate-limit-exceeded" => Dinie::RateLimitError,
        "https://docs.dinie.com/errors/internal" => Dinie::ServerError
      }.freeze,
      by_status: {
        400 => Dinie::BadRequestError,
        401 => Dinie::AuthError,
        403 => Dinie::PermissionError,
        404 => Dinie::NotFoundError,
        409 => Dinie::ConflictError,
        422 => Dinie::ValidationError,
        429 => Dinie::RateLimitError,
        500 => Dinie::ServerError,
        503 => Dinie::ServerError
      }.freeze,
      fallback_5xx: Dinie::ServerError
    }.freeze
  end
end

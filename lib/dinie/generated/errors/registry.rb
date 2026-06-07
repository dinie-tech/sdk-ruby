# frozen_string_literal: true

require_relative "../../runtime/errors"

module Dinie
  class AuthError < APIStatusError; end
  class BadRequestError < APIStatusError; end
  class ConflictError < APIStatusError; end
  class NotFoundError < APIStatusError; end
  class PermissionError < APIStatusError; end
  class RateLimitError < APIStatusError; end
  class ServerError < APIStatusError; end
  class ValidationError < APIStatusError; end

  module Internal
    ERROR_REGISTRY = {
      by_type: {
        "https://docs.dinie.com/errors/invalid-request" => Dinie::BadRequestError,
        "https://docs.dinie.com/errors/authentication-failed" => Dinie::AuthError,
        "https://docs.dinie.com/errors/forbidden" => Dinie::PermissionError,
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
        500 => Dinie::ServerError
      }.freeze,
      fallback_5xx: Dinie::ServerError
    }.freeze
  end
end

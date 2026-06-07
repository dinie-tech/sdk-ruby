# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "faraday/net_http_persistent"

module Dinie
  class Client
    DEFAULT_TIMEOUT_SECONDS = Internal::HttpClient::DEFAULT_TIMEOUT_SECONDS
    DEFAULT_MAX_RETRIES = Internal::HttpClient::DEFAULT_MAX_RETRIES

    def initialize(client_id: nil, client_secret: nil, code: nil, base_url: nil, timeout: DEFAULT_TIMEOUT_SECONDS,
                   max_retries: DEFAULT_MAX_RETRIES, idempotency: true, log_level: :off, logger: nil,
                   adapter: nil, token_manager: nil, connection: nil)
      @base_url = first_present(base_url, ENV.fetch("DINIE_BASE_URL", nil)) || Internal::HttpClient::DEFAULT_BASE_URL
      @options = {
        timeout: timeout, max_retries: max_retries, idempotency: idempotency,
        log_level: log_level, logger: logger, adapter: adapter
      }

      @connection = connection || build_connection(log_level: log_level, logger: logger, adapter: adapter)
      @token_manager = token_manager || build_token_manager(client_id, client_secret, code)
      @http = Internal::HttpClient.new(
        token_manager: @token_manager, base_url: @base_url, timeout: timeout,
        max_retries: max_retries, idempotency: idempotency, connection: @connection
      )
    end

    def banks
      @banks ||= Resources::Banks.new(@http)
    end

    def biometrics
      @biometrics ||= Resources::Biometrics.new(@http)
    end

    def credentials
      @credentials ||= Resources::Credentials.new(@http)
    end

    def credit_offers
      @credit_offers ||= Resources::CreditOffers.new(@http)
    end

    def customers
      @customers ||= Resources::Customers.new(@http)
    end

    def loans
      @loans ||= Resources::Loans.new(@http)
    end

    def webhook_endpoints
      @webhook_endpoints ||= Resources::WebhookEndpoints.new(@http)
    end

    def rate_limit
      @http.rate_limit
    end

    def with_options(**overrides)
      self.class.new(
        base_url: @base_url, token_manager: @token_manager, connection: @connection,
        **@options.merge(overrides)
      )
    end

    private

    def build_token_manager(client_id, client_secret, code = nil)
      resolved_id = first_present(client_id, ENV.fetch("DINIE_CLIENT_ID", nil))
      resolved_secret = first_present(client_secret, ENV.fetch("DINIE_CLIENT_SECRET", nil))
      raise Dinie::Error, "Missing Dinie client id: pass `client_id:` or set DINIE_CLIENT_ID." if resolved_id.nil?
      if resolved_secret.nil?
        raise Dinie::Error, "Missing Dinie client secret: pass `client_secret:` or set DINIE_CLIENT_SECRET."
      end

      Internal::TokenManager.new(
        client_id: resolved_id, client_secret: resolved_secret,
        base_url: @base_url, connection: @connection, code: code
      )
    end

    def build_connection(log_level:, logger:, adapter:)
      Faraday.new(url: @base_url) do |faraday|
        faraday.request :multipart
        faraday.use Internal::Middleware::Logging, level: log_level, logger: logger
        faraday.adapter(adapter || :net_http_persistent)
      end
    end

    def first_present(*candidates)
      candidates.find { |value| !value.nil? && value != "" }
    end
  end
end

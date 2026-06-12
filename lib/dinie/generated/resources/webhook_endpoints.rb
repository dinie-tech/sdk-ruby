# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/webhook_endpoint"
require_relative "../types/webhook_secret_rotation"

module Dinie
  module Resources
    # Operations on the webhook endpoints resource.
    class WebhookEndpoints
      def initialize(http)
        @http = http
      end

      # Create a webhook endpoint
      #
      # Create a webhook endpoint; the HMAC signing `secret` is returned only in this response
      #
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def create(request_options: {}, **fields)
        body = WebhookEndpoint.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/webhooks/endpoints", body:, request_options:)
        WebhookEndpointWithSecret.deserialize(raw)
      end

      # Delete a webhook endpoint
      #
      # Delete a webhook endpoint and stop all deliveries
      #
      # @param id [String] Identificador único do endpoint de webhook
      # @param request_options [Hash] Request options.
      # @return [Object]
      def delete(id, request_options: {})
        @http.request(method: :delete, path: "/webhooks/endpoints/#{id}", request_options:)
        nil
      end

      # List webhook endpoints
      #
      # List all configured webhook endpoints with URL, subscribed events, and status
      #
      # @param request_options [Hash] Request options.
      # @return [Object]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/webhooks/endpoints", query:, request_options:)
          { data: body[:data].map { |raw| WebhookEndpoint.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Retrieve a webhook endpoint
      #
      # Return details of a specific webhook endpoint including URL, events, and status
      #
      # @param id [String] Identificador único do endpoint de webhook
      # @param request_options [Hash] Request options.
      # @return [Object]
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/webhooks/endpoints/#{id}", request_options:)
        WebhookEndpoint.deserialize(raw)
      end

      # Rotate the signing secret
      #
      # Rotate the HMAC signing secret; the previous secret remains valid for the grace period
      #
      # @param id [String] Identificador único do endpoint de webhook
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def rotate_secret(id, request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/webhooks/endpoints/#{id}/rotate-secret", body:, request_options:)
        WebhookSecretRotation.deserialize(raw)
      end

      # Update a webhook endpoint
      #
      # Update URL, events, description, or status of a webhook endpoint
      #
      # @param id [String] Identificador único do endpoint de webhook
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def update(id, request_options: {}, **fields)
        body = WebhookEndpoint.serialize_update(**fields)
        raw = @http.request(method: :patch, path: "/webhooks/endpoints/#{id}", body:, request_options:)
        WebhookEndpoint.deserialize(raw)
      end
    end
  end
end

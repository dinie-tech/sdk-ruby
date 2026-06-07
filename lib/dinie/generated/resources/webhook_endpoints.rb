# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/webhook_endpoint"
require_relative "../types/webhook_secret_rotation"

module Dinie
  module Resources
    class WebhookEndpoints
      def initialize(http)
        @http = http
      end

      def create(request_options: {}, **fields)
        body = WebhookEndpoint.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/webhooks/endpoints", body:, request_options:)
        WebhookEndpointWithSecret.deserialize(raw)
      end

      def delete(id, request_options: {})
        @http.request(method: :delete, path: "/webhooks/endpoints/#{id}", request_options:)
        nil
      end

      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/webhooks/endpoints", query:, request_options:)
          { data: body[:data].map { |raw| WebhookEndpoint.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/webhooks/endpoints/#{id}", request_options:)
        WebhookEndpoint.deserialize(raw)
      end

      def rotate_secret(id, request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/webhooks/endpoints/#{id}/rotate-secret", body:, request_options:)
        WebhookSecretRotation.deserialize(raw)
      end

      def update(id, request_options: {}, **fields)
        body = WebhookEndpoint.serialize_update(**fields)
        raw = @http.request(method: :patch, path: "/webhooks/endpoints/#{id}", body:, request_options:)
        WebhookEndpoint.deserialize(raw)
      end
    end
  end
end

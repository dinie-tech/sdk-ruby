# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/webhook_endpoint"

module Dinie
  module Resources
    # `Dinie::Resources::WebhookEndpoints` — the `client.webhook_endpoints` resource: REST
    # management of webhook endpoints (`we_…`) (architecture §3.2). Ports `sdk-js`
    # `src/generated/resources/webhook-endpoints.ts`. Copies the resource pattern established by the
    # {Dinie::Resources::Customers} exemplar (story 007). Hand-authored in V0.3, regenerated in V0.5.
    #
    # ── NOT the webhook RUNTIME ──
    # This is the MANAGEMENT surface — create/configure/delete the endpoints Dinie delivers events
    # to. It is DISTINCT from event RECEPTION: verifying + parsing a delivered event is
    # `Dinie::Webhooks.extract` (runtime, story 011). This resource never touches the `Events::*`
    # union.
    #
    # ── Surface (frozen-surface.md) ──
    #   * `create(**fields, request_options:)`                  → {WebhookEndpointWithSecret} (201, idempotent)
    #   * `list(limit:, starting_after:, request_options:)`     → {Dinie::Page}<{WebhookEndpoint}>
    #   * `retrieve(id, request_options:)`                      → {WebhookEndpoint}
    #   * `update(id, **fields, request_options:)`              → {WebhookEndpoint} (idempotent)
    #   * `delete(id, request_options:)`                        → `nil` (204)
    #   * `rotate_secret(id, expire_current_in:, request_options:)` → {WebhookSecretRotation} (idempotent)
    #
    # ── Sub-path: the parent id is the 1st positional arg (architecture §3.1) ──
    # `POST /webhooks/endpoints/{id}/rotate-secret` becomes `rotate_secret(id, expire_current_in:,
    # request_options:)` — the `{webhook_endpoint_id}` segment is the leading positional `id`.
    #
    # ── Secret-bearing responses ──
    # `create` → {WebhookEndpointWithSecret} and `rotate_secret` → {WebhookSecretRotation} are the
    # ONLY responses carrying the HMAC `secret` (`whsec_…`, shown once). `list`/`retrieve`/`update`
    # return plain {WebhookEndpoint}s (no secret). The runtime logger redacts `secret`.
    #
    # ── Idempotency (architecture §10) ──
    # `create`/`update`/`rotate_secret` (POST/PATCH writes) auto-carry a stable `X-Idempotency-Key`
    # reused across retries. `delete` is a DELETE: naturally idempotent server-side — so it carries
    # NO auto key (the transport auto-mints only on POST/PATCH). `retrieve`/`list` are GETs.
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `generated/`. Holds the injected {Internal::HttpClient} and imports only from
    # `runtime/` (transport, paginator) and sibling `generated/` types; never the reverse.
    #
    # @example
    #   ep = client.webhook_endpoints.create(url: "https://partner.example.com/webhooks", events: ["loan.*"])
    #   ep.secret # shown once — store it securely
    #   client.webhook_endpoints.list.each { |e| puts e.url }
    #   client.webhook_endpoints.update("we_…", status: "disabled")
    #   rotation = client.webhook_endpoints.rotate_secret("we_…", expire_current_in: 7_200)
    #   client.webhook_endpoints.delete("we_…")
    class WebhookEndpoints
      # Path of the webhook-endpoints collection.
      WEBHOOK_ENDPOINTS_PATH = "/webhooks/endpoints"

      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # Create a webhook endpoint (`POST /webhooks/endpoints`). Dumps a
      # `CreateWebhookEndpointRequest` and hydrates the returned {WebhookEndpointWithSecret} — the
      # ONLY response carrying the signing `secret` (store it securely; it cannot be retrieved
      # again). The transport auto-carries an `X-Idempotency-Key`.
      #
      # @param fields [Hash{Symbol => Object}] `url:` (required) + `events:` (Array<String>) +
      #   `description:` (String), both optional
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::WebhookEndpointWithSecret]
      def create(request_options: {}, **fields)
        body = WebhookEndpoint.serialize_create(**fields)
        raw = @http.request(method: :post, path: WEBHOOK_ENDPOINTS_PATH, body:, request_options:)
        WebhookEndpointWithSecret.deserialize(raw)
      end

      # List webhook endpoints (`GET /webhooks/endpoints`), auto-paginating by `starting_after`.
      # `limit` / `starting_after` default to {Internal::OMIT} and are dropped when omitted.
      #
      # @param limit [Integer, Internal::OMIT] page size
      # @param starting_after [String, Internal::OMIT] cursor — a webhook-endpoint id (`we_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Page<Dinie::WebhookEndpoint>]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: WEBHOOK_ENDPOINTS_PATH, query:, request_options:)
          { data: body[:data].map { |raw| WebhookEndpoint.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Retrieve a webhook endpoint by id (`GET /webhooks/endpoints/{id}`).
      #
      # @param id [String] the webhook-endpoint id (`we_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::WebhookEndpoint]
      # @raise [Dinie::NotFoundError] when no endpoint has that id
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: endpoint_path(id), request_options:)
        WebhookEndpoint.deserialize(raw)
      end

      # Update a webhook endpoint's URL, events, description, or status (`PATCH
      # /webhooks/endpoints/{id}`). Dumps an `UpdateWebhookEndpointRequest` — only the keys the
      # caller set are sent (PATCH semantics) — and hydrates the full updated {WebhookEndpoint}. The
      # transport auto-carries an `X-Idempotency-Key`.
      #
      # @param id [String] the webhook-endpoint id (`we_…`), 1st positional arg
      # @param fields [Hash{Symbol => Object}] `url:` / `events:` / `description:` / `status:`, all optional
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::WebhookEndpoint]
      def update(id, request_options: {}, **fields)
        body = WebhookEndpoint.serialize_update(**fields)
        raw = @http.request(method: :patch, path: endpoint_path(id), body:, request_options:)
        WebhookEndpoint.deserialize(raw)
      end

      # Delete a webhook endpoint and stop all deliveries (`DELETE /webhooks/endpoints/{id}`).
      # Returns `nil` (the contract replies `204` with an empty body). A DELETE carries NO auto
      # idempotency key.
      #
      # @param id [String] the webhook-endpoint id (`we_…`)
      # @param request_options [Hash] per-call overrides
      # @return [nil]
      # @raise [Dinie::NotFoundError] when no endpoint has that id
      def delete(id, request_options: {})
        @http.request(method: :delete, path: endpoint_path(id), request_options:)
        nil
      end

      # Rotate the HMAC signing secret (`POST /webhooks/endpoints/{id}/rotate-secret`). The previous
      # secret stays valid for a grace period — `expire_current_in:` (seconds) overrides the server
      # default; omit it to take the default. Hydrates the returned {WebhookSecretRotation} carrying
      # the new secret (shown once) and the old secret's expiry. The transport auto-carries an
      # `X-Idempotency-Key`.
      #
      # @param id [String] the webhook-endpoint id (`we_…`), 1st positional arg
      # @param expire_current_in [Integer, Internal::OMIT] grace seconds for the previous secret
      #   (default 3600, max 86400 — server-enforced)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::WebhookSecretRotation]
      def rotate_secret(id, expire_current_in: Internal::OMIT, request_options: {})
        body = WebhookSecretRotation.serialize_rotate_secret(expire_current_in:)
        raw = @http.request(method: :post, path: "#{endpoint_path(id)}/rotate-secret", body:, request_options:)
        WebhookSecretRotation.deserialize(raw)
      end

      private

      # Path of a single webhook endpoint (sub-paths hang off this).
      def endpoint_path(id)
        "#{WEBHOOK_ENDPOINTS_PATH}/#{id}"
      end
    end
  end
end

# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/credential"

module Dinie
  module Resources
    # `Dinie::Resources::Credentials` — the `client.credentials` resource: API-key management
    # (`dinie_ci_…`) (architecture §3.2). Ports `sdk-js` `src/generated/resources/credentials.ts`.
    # Copies the resource pattern established by the {Dinie::Resources::Customers} exemplar (story
    # 007). Hand-authored in V0.3, regenerated in V0.5.
    #
    # ── Surface (frozen-surface.md) ──
    #   * `create(**fields, request_options:)`                 → {CredentialWithSecret} (201, idempotent)
    #   * `list(limit:, starting_after:, request_options:)`    → {Dinie::Page}<{Credential}>
    #   * `revoke(client_id, request_options:)`                → `nil` (204)
    #
    # ── `/auth` path, `client.credentials` surface (architecture §3.2) ──
    # The collection lives at `/auth/credentials`, but the operations are grouped under
    # `client.credentials` (the `/auth/token` op is internal — the {Internal::TokenManager}, never
    # a public method).
    #
    # ── Secret-bearing creation ──
    # `create` returns {CredentialWithSecret} — the only response that carries `client_secret`
    # (shown once). `list` returns plain {Credential}s (no secret). The runtime logger redacts
    # `client_secret`.
    #
    # ── Idempotency (architecture §10) ──
    # `create` (POST write) auto-carries a stable `X-Idempotency-Key` reused across retries.
    # `revoke` is a DELETE: naturally idempotent server-side, marked "—" in the surface — so it
    # carries NO auto key (the transport auto-mints only on POST/PATCH). `list` is a GET (no key).
    #
    # ── `revoke` 409 (`last_active_credential`) / 404 (`credential_not_found`) ──
    # Revoking the last active credential fails `409 Conflict`; an unknown id fails `404`. No new
    # error class is needed: the runtime maps `409` → {Dinie::ConflictError} and `404` →
    # {Dinie::NotFoundError}, and the partner discriminates via `err.code`.
    #
    # ── runtime ↔ generated boundary (architecture §4) ──
    # Lives in `generated/`. Holds the injected {Internal::HttpClient} and imports only from
    # `runtime/` (transport, paginator) and sibling `generated/` types; never the reverse.
    #
    # @example
    #   created = client.credentials.create(name: "ci/cd deploy key")
    #   created.client_secret # shown once — store it securely
    #   client.credentials.list.each { |cred| puts cred.id }
    #   client.credentials.revoke("dinie_ci_…")
    class Credentials
      # Path of the credentials collection.
      CREDENTIALS_PATH = "/auth/credentials"

      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # Create an API credential (`POST /auth/credentials`). Dumps a `CreateCredentialRequest` and
      # hydrates the returned {CredentialWithSecret} — the ONLY response carrying `client_secret`
      # (store it securely; it cannot be retrieved again). The transport auto-carries an
      # `X-Idempotency-Key`.
      #
      # @param fields [Hash{Symbol => Object}] `name:` (required) + `expires_at:` (Integer / `nil`,
      #   optional — `nil` = never expires, omit = server default)
      # @param request_options [Hash] per-call overrides (timeout/headers/idempotency_key/max_retries)
      # @return [Dinie::CredentialWithSecret]
      def create(request_options: {}, **fields)
        body = Credential.serialize_create(**fields)
        raw = @http.request(method: :post, path: CREDENTIALS_PATH, body:, request_options:)
        CredentialWithSecret.deserialize(raw)
      end

      # List API credentials (`GET /auth/credentials`), auto-paginating by `starting_after`.
      # `limit` / `starting_after` default to {Internal::OMIT} and are dropped when omitted. Each
      # item is a {Credential} (no secret).
      #
      # @param limit [Integer, Internal::OMIT] page size
      # @param starting_after [String, Internal::OMIT] cursor — a credential id (`dinie_ci_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Page<Dinie::Credential>]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: CREDENTIALS_PATH, query:, request_options:)
          { data: body[:data].map { |raw| Credential.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Revoke an API credential immediately and permanently (`DELETE
      # /auth/credentials/{client_id}`). Returns `nil` (the contract replies `204` with an empty
      # body). `client_id` is the **1st positional argument** (architecture §3.2). A DELETE carries
      # NO auto idempotency key.
      #
      # @param client_id [String] the credential to revoke (`dinie_ci_…`), 1st positional arg
      # @param request_options [Hash] per-call overrides
      # @return [nil]
      # @raise [Dinie::ConflictError] when revoking the last active credential (`last_active_credential`)
      # @raise [Dinie::NotFoundError] when no credential has that id (`credential_not_found`)
      def revoke(client_id, request_options: {})
        @http.request(method: :delete, path: "#{CREDENTIALS_PATH}/#{client_id}", request_options:)
        nil
      end
    end
  end
end

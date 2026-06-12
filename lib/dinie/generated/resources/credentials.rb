# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/credential"

module Dinie
  module Resources
    # Operations on the credentials resource.
    class Credentials
      def initialize(http)
        @http = http
      end

      # Create a new API key
      #
      # Create a new credential pair; the `client_secret` is shown only once in the response
      #
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def create(request_options: {}, **fields)
        body = Credential.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/auth/credentials", body:, request_options:)
        CredentialWithSecret.deserialize(raw)
      end

      # List API keys
      #
      # Return all API credentials for the authenticated partner
      #
      # @param request_options [Hash] Request options.
      # @return [Object]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/auth/credentials", query:, request_options:)
          { data: body[:data].map { |raw| Credential.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Revoke an API key
      #
      # Immediately and permanently revoke an API credential
      #
      # @param client_id [String] The resource ID.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def revoke(client_id, request_options: {})
        @http.request(method: :delete, path: "/auth/credentials/#{client_id}", request_options:)
        nil
      end
    end
  end
end

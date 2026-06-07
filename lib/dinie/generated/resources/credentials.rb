# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../types/credential"

module Dinie
  module Resources
    class Credentials
      def initialize(http)
        @http = http
      end

      def create(request_options: {}, **fields)
        body = Credential.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/auth/credentials", body:, request_options:)
        CredentialWithSecret.deserialize(raw)
      end

      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {})
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/auth/credentials", query:, request_options:)
          { data: body[:data].map { |raw| Credential.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      def revoke(client_id, request_options: {})
        @http.request(method: :delete, path: "/auth/credentials/#{client_id}", request_options:)
        nil
      end
    end
  end
end

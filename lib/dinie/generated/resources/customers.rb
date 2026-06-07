# frozen_string_literal: true

require_relative "../../runtime/multipart"
require_relative "../../runtime/paginator"
require_relative "../types/biometrics_session"
require_relative "../types/credit_offer"
require_relative "../types/customer"
require_relative "../types/customer_bank_account"
require_relative "../types/kyc"
require_relative "../types/kyc_attachment_response"

module Dinie
  module Resources
    class Customers
      def initialize(http)
        @http = http
      end

      def create(request_options: {}, **fields)
        body = Customer.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/customers", body:, request_options:)
        Customer.deserialize(raw)
      end

      def create_biometrics_session(id, request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/customers/#{id}/biometrics", body:, request_options:)
        BiometricsSession.deserialize(raw)
      end

      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after, **filters }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/customers", query:, request_options:)
          { data: body[:data].map { |raw| Customer.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{id}", request_options:)
        Customer.deserialize(raw)
      end

      def retrieve_bank_account(id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{id}/bank-account", request_options:)
        CustomerBankAccount.deserialize(raw)
      end

      def start_kyc_review(id, request_options: {})
        @http.request(method: :post, path: "/customers/#{id}/kyc-review", request_options:)
        nil
      end

      def update(id, request_options: {}, **fields)
        body = Customer.serialize_update(**fields)
        raw = @http.request(method: :patch, path: "/customers/#{id}", body:, request_options:)
        Customer.deserialize(raw)
      end

      def upsert_bank_account(id, request_options: {}, **fields)
        body = CustomerBankAccount.serialize_upsert_bank_account(**fields)
        raw = @http.request(method: :post, path: "/customers/#{id}/bank-account", body:, request_options:)
        CustomerBankAccount.deserialize(raw)
      end

      def credit_offers
        @credit_offers ||= CreditOffers.new(@http)
      end

      def kyc_attachments
        @kyc_attachments ||= KycAttachments.new(@http)
      end

      class CreditOffers
        def initialize(http)
          @http = http
        end

        def list(customer_id, limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
          path = "/customers/#{customer_id}/credit-offers"
          fetch_page = lambda do |cursor|
            query = { limit:, starting_after: cursor || starting_after, **filters }
                    .reject { |_key, value| Internal.omitted?(value) }
            body = @http.request(method: :get, path:, query:, request_options:)
            { data: body[:data].map { |raw| CreditOffer.deserialize(raw) }, has_more: body[:has_more] }
          end
          Dinie::Page.from_fetch(fetch_page)
        end
      end

      class KycAttachments
        def initialize(http)
          @http = http
        end

        def create(customer_id, request_options: {}, **upload)
          form = Dinie.serialize_kyc_upload(**upload)
          body = Dinie::Internal::Multipart.new(fields: form.fields, file: form.file)
          raw = @http.request(method: :post, path: "/customers/#{customer_id}/kyc-attachments", body:, request_options:)
          KycAttachmentResponse.deserialize(raw)
        end

        def upload_selfie(customer_id, request_options: {}, **fields)
          body = fields
          raw = @http.request(method: :post, path: "/customers/#{customer_id}/kyc-attachments/selfie", body:,
                              request_options:)
          KycAttachmentResponse.deserialize(raw)
        end
      end
    end
  end
end

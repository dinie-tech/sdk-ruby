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
    # Operations on the customers resource.
    class Customers
      def initialize(http)
        @http = http
      end

      # Register a new customer
      #
      # Register a new customer in `creating` status, idempotent on CPF
      #
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def create(request_options: {}, **fields)
        body = Customer.serialize_create(**fields)
        raw = @http.request(method: :post, path: "/customers", body:, request_options:)
        Customer.deserialize(raw)
      end

      # Create a biometrics capture session
      #
      # Generate a single-use bootstrap code for the customer-facing biometrics flow. The response includes a `session_url` the partner can embed or redirect to — the kyc-app reads the code from the URL and exchanges it for a scoped session token via `POST /biometrics/session-exchange`.
      #
      # @param id [String] Identificador único do cliente
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def create_biometrics_session(id, request_options: {}, **fields)
        body = fields
        raw = @http.request(method: :post, path: "/customers/#{id}/biometrics", body:, request_options:)
        BiometricsSession.deserialize(raw)
      end

      # List customers
      #
      # List and search customers with optional filters for `cpf`, `external_id`, and `status`
      #
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
        fetch_page = lambda do |cursor|
          query = { limit:, starting_after: cursor || starting_after, **filters }
                  .reject { |_key, value| Internal.omitted?(value) }
          body = @http.request(method: :get, path: "/customers", query:, request_options:)
          { data: body[:data].map { |raw| Customer.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Retrieve a customer
      #
      # Return the full customer object including registration data, status, and KYC progress
      #
      # @param id [String] Identificador único do cliente
      # @param request_options [Hash] Request options.
      # @return [Object]
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{id}", request_options:)
        Customer.deserialize(raw)
      end

      # Get customer bank account
      #
      # Return the bank account currently linked to this customer, if one exists.
      #
      # @param id [String] Identificador único do cliente
      # @param request_options [Hash] Request options.
      # @return [Object]
      def retrieve_bank_account(id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{id}/bank-account", request_options:)
        CustomerBankAccount.deserialize(raw)
      end

      # Submit documents for KYC review
      #
      # Signal that all KYC documents have been uploaded and are ready for review. Submits documents to the verification pipeline. Also handles resubmission after document corrections.
      #
      # @param id [String] Identificador único do cliente
      # @param request_options [Hash] Request options.
      # @return [Object]
      def start_kyc_review(id, request_options: {})
        @http.request(method: :post, path: "/customers/#{id}/kyc-review", request_options:)
        nil
      end

      # Update customer data
      #
      # Update customer fields such as email or phone; `cpf`, `cnpj`, `name`, `trading_name`, and `external_id` are read-only
      #
      # @param id [String] Identificador único do cliente
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
      def update(id, request_options: {}, **fields)
        body = Customer.serialize_update(**fields)
        raw = @http.request(method: :patch, path: "/customers/#{id}", body:, request_options:)
        Customer.deserialize(raw)
      end

      # Create or update customer bank account
      #
      # Create or update the bank account linked to this customer. This endpoint is available to biometrics session tokens so the kyc-app can collect disbursement bank data.
      #
      # @param id [String] Identificador único do cliente
      # @param fields [Hash] Request body fields.
      # @param request_options [Hash] Request options.
      # @return [Object]
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

      # Operations on the credit offers resource.
      class CreditOffers
        def initialize(http)
          @http = http
        end

        # List credit offers for a customer
        #
        # List credit offers for a specific customer, filterable by `status`
        #
        # @param customer_id [String] Identificador único do cliente
        # @param fields [Hash] Request body fields.
        # @param request_options [Hash] Request options.
        # @return [Object]
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

      # Operations on the kyc attachments resource.
      class KycAttachments
        def initialize(http)
          @http = http
        end

        # Upload a KYC attachment
        #
        # Upload a KYC attachment for the customer via `multipart/form-data`. For document requirements, send a `file`. For data-type requirements (e.g. email), send a `value` instead.
        #
        # @param customer_id [String] Identificador único do cliente
        # @param fields [Hash] Request body fields.
        # @param request_options [Hash] Request options.
        # @return [Object]
        def create(customer_id, request_options: {}, **upload)
          form = Dinie.serialize_kyc_upload(**upload)
          body = Dinie::Internal::Multipart.new(fields: form.fields, file: form.file)
          raw = @http.request(method: :post, path: "/customers/#{customer_id}/kyc-attachments", body:, request_options:)
          KycAttachmentResponse.deserialize(raw)
        end

        # Upload a KYC selfie
        #
        # Session-only upload of a selfie for biometric validation. Counterpart of the polymorphic `/kyc-attachments` route, dedicated to selfies: `evidence_type` (`selfie`) and `attachment_type` (`photo`) are implicit, so the partner only supplies `requirement_id` (`selfie_{subject_id}`) and the `file`. Requires a session token bound to the customer — a partner bearer is denied (403), even with `kyc:upload`.
        #
        # @param customer_id [String] Identificador único do cliente
        # @param fields [Hash] Request body fields.
        # @param request_options [Hash] Request options.
        # @return [Object]
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

# frozen_string_literal: true

require_relative "../../runtime/paginator"
require_relative "../../runtime/multipart"
require_relative "../types/customer"
require_relative "../types/customer_bank_account"
require_relative "../types/biometrics_session"
require_relative "../types/credit_offer"
require_relative "../types/kyc"

# `Dinie::Resources::Customers` — the largest resource on the frozen surface (architecture §3.1,
# §3.2). Ports `sdk-js` `src/generated/resources/customers.ts`. This is THE exemplar resource:
# stories 008/010 copy its shape (how a resource holds the injected `HttpClient`, serializes via
# the request dumps from the types, deserializes responses through the type `deserialize`, and
# wires subresources). Hand-authored in V0.3, regenerated in V0.5.
#
# ── How a resource is wired (the pattern 008/010 copy) ──
# A resource is constructed with the shared {Dinie::Internal::HttpClient} (`@http`) that the
# {Dinie::Client} owns. Every method:
#   1. dumps its kwargs to a wire body via the type's `serialize_*` (POST/PATCH only);
#   2. calls `@http.request(method:, path:, query:, body:, request_options:)` — the transport adds
#      auth, idempotency (auto on POST/PATCH), retries, and returns the raw symbol-keyed body;
#   3. hydrates the raw body through the type's `deserialize` and returns the typed PORO (RB7 —
#      sync, the object directly, never a Promise).
#
# ── Pagination (story 005 pattern) ──
# `list` / `credit_offers.list` build a `fetch_page` closure mapping a cursor to the
# `starting_after` query param and return `Dinie::Page.from_fetch(fetch_page)`. `cursor == nil` ⇒
# first page (uses the caller's `starting_after`, if any); otherwise the cursor is the `id` of the
# last item of the previous page. The list end-of-data signal is `has_more`, never `data.length`.
#
# ── Subresources (architecture §3.1) ──
# `customers.credit_offers` and `customers.kyc_attachments` are nested objects holding the SAME
# `@http`; the parent `customer_id` is their **first positional argument**, the rest kwargs. The
# same shape backs `loans.transactions` (story 008).
#
# ── KYC block (story 009) ──
# `start_kyc_review` (POST `/customers/{id}/kyc-review` → 202, no content → `nil`) and
# `kyc_attachments.create` (multipart POST `/customers/{id}/kyc-attachments` → `Kyc::AttachmentResponse`)
# are implemented here over the KYC types in `../types/kyc/`. The upload serializes the discriminated
# `evidence_type` union to a field-map ({Dinie::Kyc.serialize_upload}) and ships it as
# `multipart/form-data` via {Dinie::Internal::Multipart} (the runtime seam). `Customer.kyc` hydrates
# through the same discriminated union ({Dinie::Kyc.deserialize_requirement}).
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports only from `runtime/` (the transport + paginator) and sibling
# `generated/` types — never ad-hoc transport.
module Dinie
  module Resources
    # Customers + KYC + bank-account + biometrics + the customer credit-offers subresource.
    class Customers
      # @param http [Dinie::Internal::HttpClient] the shared transport owned by {Dinie::Client}
      def initialize(http)
        @http = http
      end

      # Register a new customer (`POST /customers`). Idempotent on CPF; the transport auto-carries
      # an `X-Idempotency-Key`. The four required fields mirror `CreateCustomerRequest`; `name` /
      # `external_id` default to {Dinie::Internal::OMIT} and are dropped when omitted.
      #
      # @param email [String] required contact email
      # @param phone [String] required contact phone, E.164
      # @param cpf [String] required customer CPF
      # @param cnpj [String] required company CNPJ
      # @param name [String, Internal::OMIT] optional display name (auto-fetched from CPF when omitted)
      # @param external_id [String, Internal::OMIT] optional partner reference
      # @param request_options [Hash] per-call overrides (timeout/headers/idempotency_key/max_retries)
      # @return [Dinie::Customer]
      def create(email:, phone:, cpf:, cnpj:, name: Internal::OMIT, external_id: Internal::OMIT, request_options: {})
        body = Customer.serialize_create(email:, phone:, cpf:, cnpj:, name:, external_id:)
        raw = @http.request(method: :post, path: "/customers", body:, request_options:)
        Customer.deserialize(raw)
      end

      # List and search customers (`GET /customers`), auto-paginating by `starting_after`. Optional
      # filters (`cpf`, `external_id`, `status`, `sort`, `order`) pass through as query params.
      #
      # @param limit [Integer, Internal::OMIT] page size (1–100)
      # @param starting_after [String, Internal::OMIT] cursor — the `id` of the last item seen
      # @param filters [Hash{Symbol => Object}] additional query filters (`cpf:`, `status:`, …)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Page<Dinie::Customer>]
      def list(limit: Internal::OMIT, starting_after: Internal::OMIT, request_options: {}, **filters)
        fetch_page = lambda do |cursor|
          query = paginated_query(limit:, starting_after:, cursor:, filters:)
          body = @http.request(method: :get, path: "/customers", query:, request_options:)
          { data: body[:data].map { |raw| Customer.deserialize(raw) }, has_more: body[:has_more] }
        end
        Dinie::Page.from_fetch(fetch_page)
      end

      # Retrieve the full customer object (`GET /customers/{id}`), including registration data,
      # status, and KYC progress (`kyc` is a raw pass-through until story 009 refines it).
      #
      # @param id [String] the customer id (`cust_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Customer]
      def retrieve(id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{id}", request_options:)
        Customer.deserialize(raw)
      end

      # Update mutable customer fields (`PATCH /customers/{id}`) — `email` / `phone`; `cpf`, `cnpj`,
      # `name`, `trading_name`, and `external_id` are read-only. Only the fields the caller sets are
      # sent (R-OPTIONAL). The transport auto-carries an `X-Idempotency-Key`.
      #
      # @param id [String] the customer id (`cust_…`)
      # @param fields [Hash{Symbol => Object}] mutable fields (`email:`, `phone:`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::Customer]
      def update(id, request_options: {}, **fields)
        body = Customer.serialize_update(**fields)
        raw = @http.request(method: :patch, path: "/customers/#{id}", body:, request_options:)
        Customer.deserialize(raw)
      end

      # Retrieve the bank account linked to a customer (`GET /customers/{id}/bank-account`). A
      # singleton (flat, not paginated).
      #
      # @param customer_id [String] the customer id (`cust_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::CustomerBankAccount]
      def retrieve_bank_account(customer_id, request_options: {})
        raw = @http.request(method: :get, path: "/customers/#{customer_id}/bank-account", request_options:)
        CustomerBankAccount.deserialize(raw)
      end

      # Create or update the customer's disbursement bank account
      # (`POST /customers/{id}/bank-account`). The transport auto-carries an `X-Idempotency-Key`.
      # All five fields are required (`CustomerBankAccountRequest`).
      #
      # @param customer_id [String] the customer id (`cust_…`)
      # @param fields [Hash{Symbol => Object}] `bank_id:`, `branch:`, `digit:`, `kind:`, `number:`
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::CustomerBankAccount]
      def upsert_bank_account(customer_id, request_options: {}, **fields)
        body = CustomerBankAccount.serialize_upsert(**fields)
        raw = @http.request(method: :post, path: "/customers/#{customer_id}/bank-account", body:, request_options:)
        CustomerBankAccount.deserialize(raw)
      end

      # Generate a temporary biometrics-capture session (`POST /customers/{id}/biometrics`). A
      # singleton; the endpoint is body-less (the session is minted from the path customer). The
      # transport auto-carries an `X-Idempotency-Key`.
      #
      # @param customer_id [String] the customer id (`cust_…`)
      # @param request_options [Hash] per-call overrides
      # @return [Dinie::BiometricsSession]
      def create_biometrics_session(customer_id, request_options: {})
        raw = @http.request(method: :post, path: "/customers/#{customer_id}/biometrics", request_options:)
        BiometricsSession.deserialize(raw)
      end

      # KYC review trigger (`POST /customers/{id}/kyc-review`). Signals that all KYC documents are
      # uploaded and ready for review (also handles resubmission after corrections). Body-less; the
      # endpoint returns 202 with no content, so this returns `nil`. POST → the transport
      # auto-carries an `X-Idempotency-Key` (idempotent).
      #
      # @param customer_id [String] the customer id (`cust_…`)
      # @param request_options [Hash] per-call overrides
      # @return [nil] (202 — no content)
      def start_kyc_review(customer_id, request_options: {})
        @http.request(method: :post, path: "/customers/#{customer_id}/kyc-review", request_options:)
        nil
      end

      # The customer credit-offers subresource (`customers.credit_offers`).
      #
      # @return [Dinie::Resources::Customers::CreditOffers]
      def credit_offers
        @credit_offers ||= CreditOffers.new(@http)
      end

      # The KYC attachments subresource (`customers.kyc_attachments`) — shell → story 009.
      #
      # @return [Dinie::Resources::Customers::KycAttachments]
      def kyc_attachments
        @kyc_attachments ||= KycAttachments.new(@http)
      end

      private

      # Build the query hash for a paginated list request: the caller's `limit` plus the cursor
      # (`cursor` wins over the caller's `starting_after`) and any extra filters, dropping every
      # {Dinie::Internal::OMIT} value so omitted params never reach the wire.
      #
      # @return [Hash{Symbol => Object}]
      def paginated_query(limit:, starting_after:, cursor:, filters:)
        { limit:, starting_after: cursor || starting_after, **filters }
          .reject { |_key, value| Internal.omitted?(value) }
      end

      # `customers.credit_offers` — list a single customer's credit offers (architecture §3.1,
      # §3.2). Holds the same injected `@http`; `customer_id` is the first positional argument.
      class CreditOffers
        # @param http [Dinie::Internal::HttpClient] the shared transport
        def initialize(http)
          @http = http
        end

        # List a customer's credit offers (`GET /customers/{id}/credit-offers`), auto-paginating by
        # `starting_after`. Optional `status` filter passes through as a query param.
        #
        # @param customer_id [String] the customer id (`cust_…`) — first positional argument
        # @param limit [Integer, Internal::OMIT] page size (1–100)
        # @param starting_after [String, Internal::OMIT] cursor — the `id` of the last item seen
        # @param filters [Hash{Symbol => Object}] additional query filters (`status:`)
        # @param request_options [Hash] per-call overrides
        # @return [Dinie::Page<Dinie::CreditOffer>]
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

      # `customers.kyc_attachments` — the KYC attachment-upload subresource (story 009). Holds the
      # same injected `@http`; `customer_id` is the first positional argument.
      class KycAttachments
        # @param http [Dinie::Internal::HttpClient] the shared transport
        def initialize(http)
          @http = http
        end

        # Upload a KYC attachment (`POST /customers/{id}/kyc-attachments`, `multipart/form-data` →
        # 201). The `**upload` kwargs are one member of the discriminated `evidence_type` union
        # (architecture §6.3): `evidence_type:`, `requirement_id:`, `attachment_type:`, plus either a
        # binary `file:` (the nine document variants) or a scalar `value:` (the `email` variant).
        # {Dinie::Kyc.serialize_upload} dispatches on `evidence_type` to the right multipart
        # field-map; {Dinie::Internal::Multipart} ships it as `multipart/form-data`. POST → the
        # transport auto-carries an `X-Idempotency-Key` (idempotent). The response wraps the FULL
        # post-upload requirement state.
        #
        # @param customer_id [String] the customer id (`cust_…`) — first positional argument
        # @param upload [Hash{Symbol => Object}] one upload-union member —
        #   `evidence_type:`, `requirement_id:`, `attachment_type:`, and `file:` or `value:`
        # @param request_options [Hash] per-call overrides
        # @return [Dinie::Kyc::AttachmentResponse] the post-upload requirement state
        # @raise [Dinie::Error] when `evidence_type` is unknown or the variant's required part is missing
        # @example Upload the front of a physical CNH
        #   client.customers.kyc_attachments.create(
        #     "cust_…", evidence_type: "cnh", requirement_id: "identity_003…",
        #     attachment_type: "front", file: File.open("cnh-front.jpg")
        #   )
        def create(customer_id, request_options: {}, **upload)
          form = Dinie::Kyc.serialize_upload(**upload)
          body = Dinie::Internal::Multipart.new(fields: form.fields, file: form.file)
          raw = @http.request(method: :post, path: "/customers/#{customer_id}/kyc-attachments", body:, request_options:)
          Dinie::Kyc::AttachmentResponse.deserialize(raw)
        end
      end
    end
  end
end

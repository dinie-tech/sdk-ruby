# frozen_string_literal: true

# Surface specs for `Dinie::Resources::Customers` (story 007) — the exemplar resource tier
# (architecture §14, "surface per resource"). One pass per method: correct path/verb/body,
# idempotency on POST/PATCH, pagination on the `list`s, hydrate of the response, a typed error,
# and the KYC seam (shells raise → story 009). Driven through a real `Dinie::Client` with the
# token endpoint + each resource endpoint stubbed via WebMock (zero network).
RSpec.describe Dinie::Resources::Customers do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_url) { "#{base_url}/auth/token" }
  let(:customer_id) { "cust_550e8400e29b41d4a716446655440000" }
  let(:client) { Dinie::Client.new(client_id: "id-1", client_secret: "secret-1", base_url:) }
  subject(:customers) { client.customers }

  # Every resource call needs a Bearer token first; stub the OAuth2 endpoint once.
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("DINIE_BASE_URL", nil).and_return(nil)
    stub_request(:post, token_url)
      .to_return(status: 200, body: JSON.generate(access_token: "tok-1", token_type: "bearer", expires_in: 3_600))
  end

  # ── fixtures (values from `openapi.yaml @ 3fcfd83` schema examples) ──
  def customer_wire(id: customer_id, status: "active")
    {
      id:, status:, cpf: "123.456.789-00", cnpj: "12.345.678/0001-90",
      name: "João Silva", email: "joao@example.com", phone: "+5511999999999",
      trading_name: "Loja do João", external_id: "partner-ref-123", kyc: [],
      created_at: 1_709_546_400, updated_at: 1_709_632_800
    }
  end

  let(:bank_account_wire) do
    {
      bank_id: "001", bank_name: "Banco do Brasil", branch: "0001", digit: "0",
      id: "ba_550e8400e29b41d4a716446655440000", kind: "checking", number: "1234567",
      updated_at: 1_709_632_800
    }
  end

  let(:biometrics_wire) do
    { session_url: "https://biometrics.dinie.com.br/session/abc123def456", expires_at: 1_741_082_400 }
  end

  def credit_offer_wire(id:)
    {
      id:, customer_id:, status: "available", approved_amount: 50_000.00, min_amount: 200.00,
      monthly_interest_rate: 3.50, installments: 12, due_date_rule: nil, valid_until: 1_775_253_599,
      created_at: 1_772_791_200, updated_at: 1_772_877_600
    }
  end

  # Asserts a request carried a non-empty `X-Idempotency-Key` (auto on POST/PATCH).
  def idempotent_request(verb, url)
    a_request(verb, url).with { |req| !req.headers["X-Idempotency-Key"].to_s.empty? }
  end

  describe "#create" do
    let(:url) { "#{base_url}/customers" }

    before { stub_request(:post, url).to_return(status: 201, body: JSON.generate(customer_wire(status: "creating"))) }

    it "POSTs the required body, drops omitted optionals, and hydrates the response" do
      customer = customers.create(email: "joao@example.com", phone: "+5511999999999",
                                  cpf: "123.456.789-00", cnpj: "12.345.678/0001-90")

      expected_body = { cnpj: "12.345.678/0001-90", cpf: "123.456.789-00",
                        email: "joao@example.com", phone: "+5511999999999" }
      expect(a_request(:post, url).with(body: expected_body)).to have_been_made
      expect(customer).to be_a(Dinie::Customer)
      expect(customer.id).to eq(customer_id)
      expect(customer.status).to eq("creating")
    end

    it "includes the optional fields when provided" do
      customers.create(email: "joao@example.com", phone: "+5511999999999", cpf: "123.456.789-00",
                       cnpj: "12.345.678/0001-90", name: "João Silva", external_id: "ref-1")

      expected_body = { cnpj: "12.345.678/0001-90", cpf: "123.456.789-00", email: "joao@example.com",
                        external_id: "ref-1", name: "João Silva", phone: "+5511999999999" }
      expect(a_request(:post, url).with(body: expected_body)).to have_been_made
    end

    it "auto-carries an idempotency key (POST)" do
      customers.create(email: "a@b.com", phone: "+5511999999999", cpf: "123.456.789-00", cnpj: "12.345.678/0001-90")
      expect(idempotent_request(:post, url)).to have_been_made
    end
  end

  describe "#retrieve" do
    let(:url) { "#{base_url}/customers/#{customer_id}" }

    it "GETs the customer by id and hydrates it" do
      stub_request(:get, url).to_return(status: 200, body: JSON.generate(customer_wire))

      customer = customers.retrieve(customer_id)

      expect(a_request(:get, url)).to have_been_made
      expect(customer).to be_a(Dinie::Customer)
      expect(customer.name).to eq("João Silva")
      expect(customer.created_at).to eq(1_709_546_400) # epoch stays Integer (R-EPOCH)
    end

    it "raises a typed NotFoundError on a 404" do
      stub_request(:get, url).to_return(
        status: 404, headers: { "Content-Type" => "application/problem+json" },
        body: JSON.generate(type: "https://docs.dinie.com/errors/not-found", title: "Not Found",
                            status: 404, detail: "Customer ID does not exist", code: "customer_not_found")
      )

      expect { customers.retrieve(customer_id) }.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "#update" do
    let(:url) { "#{base_url}/customers/#{customer_id}" }

    before { stub_request(:patch, url).to_return(status: 200, body: JSON.generate(customer_wire)) }

    it "PATCHes only the set fields and hydrates the response" do
      customer = customers.update(customer_id, email: "joao.novo@example.com")

      expect(a_request(:patch, url).with(body: { email: "joao.novo@example.com" })).to have_been_made
      expect(customer).to be_a(Dinie::Customer)
    end

    it "auto-carries an idempotency key (PATCH)" do
      customers.update(customer_id, phone: "+5511988887777")
      expect(idempotent_request(:patch, url)).to have_been_made
    end
  end

  describe "#list" do
    let(:url) { "#{base_url}/customers" }

    it "returns a Page and passes filters through as query params" do
      stub_request(:get, url).with(query: { cpf: "123.456.789-00", limit: "10" })
                             .to_return(status: 200, body: JSON.generate(data: [customer_wire], has_more: false))

      page = customers.list(cpf: "123.456.789-00", limit: 10)

      expect(page).to be_a(Dinie::Page)
      expect(page.data.map(&:class)).to eq([Dinie::Customer])
      expect(page.has_more).to be(false)
    end

    it "auto-paginates across pages by starting_after (terminating on has_more)" do
      page1 = [customer_wire(id: "cust_a"), customer_wire(id: "cust_b")]
      page2 = [customer_wire(id: "cust_c")]
      stub_request(:get, url).with(query: { limit: "2" })
                             .to_return(status: 200, body: JSON.generate(data: page1, has_more: true))
      stub_request(:get, url).with(query: { limit: "2", starting_after: "cust_b" })
                             .to_return(status: 200, body: JSON.generate(data: page2, has_more: false))

      ids = customers.list(limit: 2).auto_paging_each.map(&:id)

      expect(ids).to eq(%w[cust_a cust_b cust_c])
      expect(a_request(:get, url).with(query: { limit: "2", starting_after: "cust_b" })).to have_been_made
    end

    it "sends no cursor/limit params when none are given (OMIT dropped)" do
      stub_request(:get, url).to_return(status: 200, body: JSON.generate(data: [], has_more: false))

      customers.list.data

      expect(a_request(:get, url)).to have_been_made # no query string
    end
  end

  describe "#retrieve_bank_account" do
    let(:url) { "#{base_url}/customers/#{customer_id}/bank-account" }

    it "GETs the singleton bank account and hydrates it" do
      stub_request(:get, url).to_return(status: 200, body: JSON.generate(bank_account_wire))

      account = customers.retrieve_bank_account(customer_id)

      expect(a_request(:get, url)).to have_been_made
      expect(account).to be_a(Dinie::CustomerBankAccount)
      expect(account.bank_name).to eq("Banco do Brasil")
      expect(account.updated_at).to eq(1_709_632_800)
    end
  end

  describe "#upsert_bank_account" do
    let(:url) { "#{base_url}/customers/#{customer_id}/bank-account" }
    let(:fields) { { bank_id: "001", branch: "0001", digit: "0", kind: "checking", number: "1234567" } }

    before { stub_request(:post, url).to_return(status: 200, body: JSON.generate(bank_account_wire)) }

    it "POSTs the bank_account-wrapped body and hydrates the response" do
      account = customers.upsert_bank_account(customer_id, **fields)

      expect(a_request(:post, url).with(body: { bank_account: fields })).to have_been_made
      expect(account).to be_a(Dinie::CustomerBankAccount)
    end

    it "auto-carries an idempotency key (POST)" do
      customers.upsert_bank_account(customer_id, **fields)
      expect(idempotent_request(:post, url)).to have_been_made
    end
  end

  describe "#create_biometrics_session" do
    let(:url) { "#{base_url}/customers/#{customer_id}/biometrics" }

    it "POSTs body-less and hydrates the session" do
      stub_request(:post, url).to_return(status: 200, body: JSON.generate(biometrics_wire))

      session = customers.create_biometrics_session(customer_id)

      expect(a_request(:post, url).with { |req| req.body.nil? || req.body.empty? }).to have_been_made
      expect(session).to be_a(Dinie::BiometricsSession)
      expect(session.session_url).to start_with("https://biometrics.dinie.com.br/")
      expect(session.expires_at).to eq(1_741_082_400)
    end
  end

  describe "#credit_offers (subresource)" do
    let(:url) { "#{base_url}/customers/#{customer_id}/credit-offers" }

    it "takes customer_id positionally and returns a Page<CreditOffer>" do
      stub_request(:get, url).with(query: { limit: "5" }).to_return(
        status: 200, body: JSON.generate(data: [credit_offer_wire(id: "co_1")], has_more: false)
      )

      page = customers.credit_offers.list(customer_id, limit: 5)

      expect(page).to be_a(Dinie::Page)
      expect(page.data.map(&:class)).to eq([Dinie::CreditOffer])
      expect(page.data.first.id).to eq("co_1")
    end

    it "auto-paginates and passes the status filter through" do
      stub_request(:get, url).with(query: { status: "available", limit: "2" }).to_return(
        status: 200, body: JSON.generate(data: [credit_offer_wire(id: "co_a"), credit_offer_wire(id: "co_b")],
                                         has_more: true)
      )
      stub_request(:get, url).with(query: { status: "available", limit: "2", starting_after: "co_b" }).to_return(
        status: 200, body: JSON.generate(data: [credit_offer_wire(id: "co_c")], has_more: false)
      )

      ids = customers.credit_offers.list(customer_id, status: "available", limit: 2).auto_paging_each.map(&:id)

      expect(ids).to eq(%w[co_a co_b co_c])
    end

    it "memoizes the subresource (holds the same shared HttpClient)" do
      expect(customers.credit_offers).to be(customers.credit_offers)
    end
  end

  describe "KYC seam → story 009 (shells)" do
    it "raises NotImplementedError from start_kyc_review" do
      expect { customers.start_kyc_review(customer_id) }
        .to raise_error(NotImplementedError, /story 009/)
    end

    it "raises NotImplementedError from kyc_attachments.create" do
      expect { customers.kyc_attachments.create(customer_id, evidence_type: "cnh") }
        .to raise_error(NotImplementedError, /story 009/)
    end

    it "exposes kyc_attachments as a memoized subresource" do
      expect(customers.kyc_attachments).to be(customers.kyc_attachments)
    end
  end
end

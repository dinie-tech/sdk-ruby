# frozen_string_literal: true

require_relative "../support/fake_token_manager"

# Surface tier for `client.loans` + the nested `loans.transactions` subresource (architecture §14).
# Each method → correct path/verb/body, idempotency on POST, pagination + positional `loan_id` on
# the subresource, hydrate of the response, typed error. Drives the REAL
# {Dinie::Internal::HttpClient} (DI seam: a {FakeTokenManager}) against WebMock — zero network.
RSpec.describe Dinie::Resources::Loans do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_manager) { FakeTokenManager.new }
  let(:http) do
    Dinie::Internal::HttpClient.new(token_manager: token_manager, base_url: base_url, sleeper: ->(_seconds) {})
  end
  let(:resource) { described_class.new(http) }
  let(:loan_id) { "ln_#{"a" * 32}" }
  let(:idempotency_key) { /\Adinie-sdk-retry-/ }

  def url(path)
    "#{base_url}#{path}"
  end

  # A complete `Loan` wire object (every required field; the required-nullable ones populated).
  def loan_wire(id:)
    {
      id: id, credit_offer_id: "co_#{"1" * 32}", customer_id: "cust_#{"a" * 32}",
      simulation_id: "sim_#{"a" * 32}", status: "awaiting_signatures", requested_amount: 25_000.0,
      principal_amount: 29_375.0, iof_amount: 1_875.0, monthly_interest_rate: 3.5,
      annual_interest_rate: 51.11, monthly_cet_rate: 2.0, annual_cet_rate: 233.18,
      total_amount: 31_989.36, installment_count: 4, installment_amount: 7_997.34,
      first_due_date: "2026-04-03", ccb_number: nil, disbursement_method: nil,
      signing_url: "https://app.clicksign.com/sign/abc", created_at: 1_700_000_000,
      updated_at: 1_700_000_100
    }
  end

  def tx_wire(id:)
    {
      id: id, loan_id: loan_id, type: "installment", status: "pending", due_date: "2026-04-03",
      amount_due: 7_997.34, amount_paid: 0.0, amount_remaining: 7_997.34, principal: 6_000.0,
      interest: 1_500.0, fees: 497.34, days_overdue: 0, paid_at: nil,
      created_at: 1_700_000_000, updated_at: 1_700_000_100
    }
  end

  describe "#create" do
    it "POSTs /loans with the 5 required fields (alphabetical) and hydrates a Loan" do
      stub_request(:post, url("/loans")).to_return(status: 201, body: JSON.generate(loan_wire(id: loan_id)))

      loan = resource.create(
        credit_offer_id: "co_#{"1" * 32}", simulation_id: "sim_#{"a" * 32}",
        installment_count: 4, installment_amount: 7_997.34, first_due_date: "2026-04-03"
      )

      expect(loan).to be_a(Dinie::Loan)
      expect(loan.status).to eq("awaiting_signatures")
      expect(a_request(:post, url("/loans")).with(body: {
                                                    credit_offer_id: "co_#{"1" * 32}",
                                                    first_due_date: "2026-04-03",
                                                    installment_amount: 7_997.34,
                                                    installment_count: 4,
                                                    simulation_id: "sim_#{"a" * 32}"
                                                  })).to have_been_made
    end

    it "carries an auto X-Idempotency-Key on the POST (architecture §10)" do
      stub_request(:post, url("/loans")).to_return(status: 201, body: JSON.generate(loan_wire(id: loan_id)))

      resource.create(
        credit_offer_id: "co_1", simulation_id: "sim_1",
        installment_count: 4, installment_amount: 7_997.34, first_due_date: "2026-04-03"
      )
      expect(a_request(:post, url("/loans")).with(headers: { "X-Idempotency-Key" => idempotency_key }))
        .to have_been_made
    end
  end

  describe "#retrieve" do
    it "GETs /loans/{id} and hydrates a Loan (nullable fields arrive as nil)" do
      stub_request(:get, url("/loans/#{loan_id}")).to_return(status: 200, body: JSON.generate(loan_wire(id: loan_id)))

      loan = resource.retrieve(loan_id)
      expect(loan.id).to eq(loan_id)
      expect(loan.ccb_number).to be_nil
      expect(loan.disbursement_method).to be_nil
    end

    it "raises a typed NotFoundError on a 404" do
      stub_request(:get, url("/loans/ln_missing"))
        .to_return(status: 404, body: JSON.generate(type: "https://docs.dinie.com/errors/not-found"))

      expect { resource.retrieve("ln_missing") }.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "#transactions" do
    it "memoizes the subresource (one HttpClient, one instance)" do
      expect(resource.transactions).to be_a(described_class::Transactions)
      expect(resource.transactions).to be(resource.transactions)
    end

    describe "#list" do
      it "GETs /loans/{loan_id}/transactions (loan_id positional) and hydrates a Page of Transaction" do
        stub_request(:get, url("/loans/#{loan_id}/transactions"))
          .to_return(status: 200, body: JSON.generate(data: [tx_wire(id: "tx_#{"1" * 32}")], has_more: false))

        page = resource.transactions.list(loan_id)
        expect(page).to be_a(Dinie::Page)
        expect(page.data.map(&:class)).to eq([Dinie::Transaction])
        expect(page.data.first.status).to eq("pending")
      end

      it "auto-paginates: follows starting_after = last id until has_more is false" do
        stub_request(:get, url("/loans/#{loan_id}/transactions")).with(query: { limit: "2" })
                                                                 .to_return(status: 200, body: JSON.generate(
                                                                   data: [tx_wire(id: "tx_#{"1" * 32}")], has_more: true
                                                                 ))
        stub_request(:get, url("/loans/#{loan_id}/transactions"))
          .with(query: { limit: "2", starting_after: "tx_#{"1" * 32}" })
          .to_return(status: 200, body: JSON.generate(data: [tx_wire(id: "tx_#{"2" * 32}")], has_more: false))

        # `#each` without a block returns an auto-paginating Enumerator (Page has no `Enumerable`).
        ids = resource.transactions.list(loan_id, limit: 2).each.map(&:id)
        expect(ids).to eq(["tx_#{"1" * 32}", "tx_#{"2" * 32}"])
      end
    end
  end

  describe "(de)serialization round-trips" do
    it "Loan.serialize_create emits the 5 required keys, alphabetical, no extras" do
      body = Dinie::Loan.serialize_create(
        credit_offer_id: "co_1", simulation_id: "sim_1",
        installment_count: 4, installment_amount: 7_997.34, first_due_date: "2026-04-03"
      )
      expect(body.keys).to eq(%i[credit_offer_id first_due_date installment_amount installment_count simulation_id])
    end

    it "Transaction.deserialize hydrates every field, keeps paid_at nil, and to_h is in R-ORDER" do
      tx = Dinie::Transaction.deserialize(tx_wire(id: "tx_1"))
      expect(tx.type).to eq("installment")
      expect(tx.paid_at).to be_nil
      expect(tx.created_at).to be_a(Integer)
      expect(tx.to_h.keys).to eq(%i[
                                   amount_due amount_paid amount_remaining created_at days_overdue
                                   due_date fees id interest loan_id paid_at principal status type
                                   updated_at
                                 ])
    end
  end
end

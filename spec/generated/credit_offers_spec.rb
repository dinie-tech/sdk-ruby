# frozen_string_literal: true

require_relative "../support/fake_token_manager"

# Surface tier for `client.credit_offers` (architecture §14 — "surface por resource"): each method
# → correct path/verb/body, pagination, idempotency on POST, hydrate of the response, typed error.
# Drives the REAL {Dinie::Internal::HttpClient} (DI seam: a {FakeTokenManager}, no token endpoint)
# against WebMock — zero network. The conformance round-trip lives in story 012, not here.
RSpec.describe Dinie::Resources::CreditOffers do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_manager) { FakeTokenManager.new }
  let(:http) do
    Dinie::Internal::HttpClient.new(token_manager: token_manager, base_url: base_url, sleeper: ->(_seconds) {})
  end
  let(:resource) { described_class.new(http) }
  let(:idempotency_key) { /\Adinie-sdk-retry-/ }

  def url(path)
    "#{base_url}#{path}"
  end

  # A complete `CreditOffer` wire object (every required field + the XOR fixed-count branch).
  def offer_wire(id:)
    {
      id: id, customer_id: "cust_#{"a" * 32}", external_id: "partner-1", status: "available",
      approved_amount: 50_000.0, min_amount: 200.0, monthly_interest_rate: 3.5,
      installments: 12, min_installments: nil, max_installments: nil, due_date_rule: nil,
      valid_until: 1_775_253_599, created_at: 1_700_000_000, updated_at: 1_700_000_100
    }
  end

  describe "#list" do
    it "GETs /credit-offers and hydrates a Page of CreditOffer" do
      stub_request(:get, url("/credit-offers"))
        .to_return(status: 200, body: JSON.generate(data: [offer_wire(id: "co_#{"1" * 32}")], has_more: false))

      page = resource.list
      expect(page).to be_a(Dinie::Page)
      expect(page.data.map(&:class)).to eq([Dinie::CreditOffer])
      expect(page.data.first.id).to eq("co_#{"1" * 32}")
      expect(page.data.first.approved_amount).to eq(50_000.0)
    end

    it "passes limit and arbitrary filters as query params, dropping omitted ones" do
      # `list` fetches the first page eagerly (story 005), so the call alone makes the request.
      stub_request(:get, url("/credit-offers"))
        .with(query: { limit: "50", customer_id: "cust_x" })
        .to_return(status: 200, body: JSON.generate(data: [], has_more: false))

      resource.list(limit: 50, customer_id: "cust_x")
      expect(a_request(:get, url("/credit-offers")).with(query: { limit: "50", customer_id: "cust_x" }))
        .to have_been_made
    end

    it "auto-paginates: follows starting_after = last id until has_more is false" do
      first = stub_request(:get, url("/credit-offers")).with(query: { limit: "2" })
                                                       .to_return(status: 200, body: JSON.generate(
                                                         data: [offer_wire(id: "co_#{"1" * 32}")], has_more: true
                                                       ))
      second = stub_request(:get, url("/credit-offers")).with(query: { limit: "2", starting_after: "co_#{"1" * 32}" })
                                                        .to_return(status: 200, body: JSON.generate(
                                                          data: [offer_wire(id: "co_#{"2" * 32}")], has_more: false
                                                        ))

      # `#each` without a block returns an Enumerator over every item of every page (Page has no
      # `Enumerable`, by design — RB8); `.map` then drives the auto-pagination.
      ids = resource.list(limit: 2).each.map(&:id)
      expect(ids).to eq(["co_#{"1" * 32}", "co_#{"2" * 32}"])
      expect(first).to have_been_made
      expect(second).to have_been_made
    end
  end

  describe "#retrieve" do
    it "GETs /credit-offers/{id} and hydrates a CreditOffer" do
      stub_request(:get, url("/credit-offers/co_#{"1" * 32}"))
        .to_return(status: 200, body: JSON.generate(offer_wire(id: "co_#{"1" * 32}")))

      offer = resource.retrieve("co_#{"1" * 32}")
      expect(offer).to be_a(Dinie::CreditOffer)
      expect(offer.status).to eq("available")
    end

    it "raises a typed NotFoundError on a 404" do
      stub_request(:get, url("/credit-offers/co_missing"))
        .to_return(status: 404, body: JSON.generate(type: "https://docs.dinie.com/errors/not-found"))

      expect { resource.retrieve("co_missing") }.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "#create_simulation" do
    let(:sim_wire) do
      {
        id: "sim_#{"a" * 32}", credit_offer_id: "co_#{"1" * 32}", requested_amount: 25_000.0,
        principal_amount: 29_375.0, interest_amount: 2_614.36, iof_amount: 1_875.0, fee_amount: 2_500.0,
        total_amount: 31_989.36, monthly_interest_rate: 3.5, annual_interest_rate: 51.11,
        monthly_cet_rate: 2.0, annual_cet_rate: 233.18, installment_count: 4, installment_amount: 7_997.34,
        first_due_date: "2026-04-03", created_at: 1_700_000_000
      }
    end

    it "POSTs /credit-offers/{id}/simulations with an alphabetical body and hydrates a Simulation" do
      stub_request(:post, url("/credit-offers/co_#{"1" * 32}/simulations"))
        .to_return(status: 201, body: JSON.generate(sim_wire))

      sim = resource.create_simulation("co_#{"1" * 32}", requested_amount: 25_000.0, installment_count: 12)

      expect(sim).to be_a(Dinie::Simulation)
      expect(sim.installment_amount).to eq(7_997.34)
      expect(a_request(:post, url("/credit-offers/co_#{"1" * 32}/simulations"))
        .with(body: { installment_count: 12, requested_amount: 25_000.0 })).to have_been_made
    end

    it "carries an auto X-Idempotency-Key on the POST (architecture §10)" do
      stub_request(:post, url("/credit-offers/co_#{"1" * 32}/simulations"))
        .to_return(status: 201, body: JSON.generate(sim_wire))

      resource.create_simulation("co_#{"1" * 32}", requested_amount: 25_000.0, installment_count: 12)
      expect(a_request(:post, url("/credit-offers/co_#{"1" * 32}/simulations"))
        .with(headers: { "X-Idempotency-Key" => idempotency_key })).to have_been_made
    end
  end

  describe "Simulation (de)serialization round-trips" do
    it "serialize_create emits the two required keys, alphabetical, no extras" do
      body = Dinie::Simulation.serialize_create(installment_count: 12, requested_amount: 25_000.0)
      expect(body).to eq(installment_count: 12, requested_amount: 25_000.0)
      expect(body.keys).to eq(%i[installment_count requested_amount])
    end

    it "deserialize hydrates every field and keeps to_h in R-ORDER" do
      wire = {
        id: "sim_1", credit_offer_id: "co_1", requested_amount: 25_000.0, principal_amount: 29_375.0,
        interest_amount: 2_614.36, iof_amount: 1_875.0, fee_amount: 2_500.0, total_amount: 31_989.36,
        monthly_interest_rate: 3.5, annual_interest_rate: 51.11, monthly_cet_rate: 2.0,
        annual_cet_rate: 233.18, installment_count: 4, installment_amount: 7_997.34,
        first_due_date: "2026-04-03", created_at: 1_700_000_000
      }
      sim = Dinie::Simulation.deserialize(wire)
      expect(sim.created_at).to be_a(Integer)
      expect(sim.first_due_date).to eq("2026-04-03")
      expect(sim.to_h.keys).to eq(%i[
                                    annual_cet_rate annual_interest_rate created_at credit_offer_id
                                    fee_amount first_due_date id installment_amount installment_count
                                    interest_amount iof_amount monthly_cet_rate monthly_interest_rate
                                    principal_amount requested_amount total_amount
                                  ])
    end
  end
end

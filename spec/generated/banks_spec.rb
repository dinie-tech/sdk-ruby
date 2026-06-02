# frozen_string_literal: true

require_relative "../support/fake_token_manager"

# Surface tier for `client.banks` (architecture §14): the single `list` method → correct
# path/verb, hydrate, and — the resource's defining trait (§11) — a FLAT `Array<Bank>`, NOT a
# {Dinie::Page}. Drives the REAL {Dinie::Internal::HttpClient} against WebMock — zero network.
RSpec.describe Dinie::Resources::Banks do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_manager) { FakeTokenManager.new }
  let(:http) do
    Dinie::Internal::HttpClient.new(token_manager: token_manager, base_url: base_url, sleeper: ->(_seconds) {})
  end
  let(:resource) { described_class.new(http) }

  def url(path)
    "#{base_url}#{path}"
  end

  # The `GET /banks` envelope — `{ data: [...] }` with NO `has_more` (the §11 discriminator).
  def banks_envelope
    {
      data: [
        { id: "001", name: "Banco do Brasil", display_name: "001 - Banco do Brasil" },
        { id: "237", name: "Bradesco", display_name: "237 - Bradesco" }
      ]
    }
  end

  describe "#list" do
    it "GETs /banks and hydrates each Bank" do
      stub_request(:get, url("/banks")).to_return(status: 200, body: JSON.generate(banks_envelope))

      banks = resource.list
      expect(banks.map(&:class)).to eq([Dinie::Bank, Dinie::Bank])
      expect(banks.first.id).to eq("001")
      expect(banks.first.display_name).to eq("001 - Banco do Brasil")
      expect(a_request(:get, url("/banks"))).to have_been_made
    end

    it "returns a FLAT Array — not a Page (the §11 determinism rule: no has_more ⇒ Array)" do
      stub_request(:get, url("/banks")).to_return(status: 200, body: JSON.generate(banks_envelope))

      banks = resource.list
      expect(banks).to be_an(Array)
      expect(banks).not_to be_a(Dinie::Page)
      # The rule itself: the `/banks` envelope carries no `has_more`, so it is NOT paginated.
      expect(Dinie::Page.paginated?(banks_envelope)).to be(false)
    end
  end
end

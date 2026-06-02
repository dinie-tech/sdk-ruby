# frozen_string_literal: true

require_relative "../support/fake_token_manager"

# Surface tier for `client.credentials` (architecture §14 — "surface por resource"): each method
# → correct path/verb/body, pagination, idempotency on POST (and its ABSENCE on DELETE), hydrate of
# the response, typed error. Drives the REAL {Dinie::Internal::HttpClient} (DI seam: a
# {FakeTokenManager}, no token endpoint) against WebMock — zero network. The conformance round-trip
# lives in story 012, not here.
RSpec.describe Dinie::Resources::Credentials do
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

  # A complete `Credential` wire object (every required field; `expires_at`/`last_used_at` nullable).
  def credential_wire(id:, secret: nil)
    base = {
      client_id: id, created_at: 1_700_000_000, expires_at: nil, id: id,
      last_used_at: nil, name: "ci/cd deploy key", status: "active", updated_at: 1_700_000_100
    }
    secret.nil? ? base : base.merge(client_secret: secret)
  end

  describe "#create" do
    let(:client_id) { "dinie_ci_#{"a" * 32}" }

    it "POSTs /auth/credentials and hydrates a CredentialWithSecret carrying the secret" do
      stub_request(:post, url("/auth/credentials"))
        .to_return(status: 201, body: JSON.generate(credential_wire(id: client_id, secret: "dinie_cs_live_abc")))

      created = resource.create(name: "ci/cd deploy key")

      expect(created).to be_a(Dinie::CredentialWithSecret)
      expect(created.client_id).to eq(client_id)
      expect(created.client_secret).to eq("dinie_cs_live_abc")
      expect(a_request(:post, url("/auth/credentials")).with(body: { name: "ci/cd deploy key" }))
        .to have_been_made
    end

    it "sends an explicit expires_at nil as JSON null (never expires) and omits it when absent" do
      stub_request(:post, url("/auth/credentials"))
        .to_return(status: 201, body: JSON.generate(credential_wire(id: client_id, secret: "s")))

      resource.create(name: "k", expires_at: nil)
      expect(a_request(:post, url("/auth/credentials"))
        .with(body: JSON.generate(expires_at: nil, name: "k"))).to have_been_made
    end

    it "carries an auto X-Idempotency-Key on the POST (architecture §10)" do
      stub_request(:post, url("/auth/credentials"))
        .to_return(status: 201, body: JSON.generate(credential_wire(id: client_id, secret: "s")))

      resource.create(name: "k")
      expect(a_request(:post, url("/auth/credentials"))
        .with(headers: { "X-Idempotency-Key" => idempotency_key })).to have_been_made
    end
  end

  describe "#list" do
    it "GETs /auth/credentials and hydrates a Page of Credential (no secret)" do
      stub_request(:get, url("/auth/credentials"))
        .to_return(status: 200, body: JSON.generate(
          data: [credential_wire(id: "dinie_ci_#{"1" * 32}")], has_more: false
        ))

      page = resource.list
      expect(page).to be_a(Dinie::Page)
      expect(page.data.map(&:class)).to eq([Dinie::Credential])
      expect(page.data.first.id).to eq("dinie_ci_#{"1" * 32}")
    end

    it "passes limit and starting_after as query params, dropping omitted ones" do
      stub_request(:get, url("/auth/credentials"))
        .with(query: { limit: "25", starting_after: "dinie_ci_#{"1" * 32}" })
        .to_return(status: 200, body: JSON.generate(data: [], has_more: false))

      resource.list(limit: 25, starting_after: "dinie_ci_#{"1" * 32}")
      expect(a_request(:get, url("/auth/credentials"))
        .with(query: { limit: "25", starting_after: "dinie_ci_#{"1" * 32}" })).to have_been_made
    end

    it "auto-paginates: follows starting_after = last id until has_more is false" do
      stub_request(:get, url("/auth/credentials")).with(query: { limit: "1" })
                                                  .to_return(status: 200, body: JSON.generate(
                                                    data: [credential_wire(id: "dinie_ci_#{"1" * 32}")], has_more: true
                                                  ))
      stub_request(:get, url("/auth/credentials"))
        .with(query: { limit: "1", starting_after: "dinie_ci_#{"1" * 32}" })
        .to_return(status: 200, body: JSON.generate(
          data: [credential_wire(id: "dinie_ci_#{"2" * 32}")], has_more: false
        ))

      ids = resource.list(limit: 1).each.map(&:id)
      expect(ids).to eq(["dinie_ci_#{"1" * 32}", "dinie_ci_#{"2" * 32}"])
    end
  end

  describe "#revoke" do
    let(:client_id) { "dinie_ci_#{"a" * 32}" }

    it "DELETEs /auth/credentials/{client_id} and returns nil (204)" do
      stub_request(:delete, url("/auth/credentials/#{client_id}")).to_return(status: 204, body: "")

      expect(resource.revoke(client_id)).to be_nil
      expect(a_request(:delete, url("/auth/credentials/#{client_id}"))).to have_been_made
    end

    it "does NOT carry an auto X-Idempotency-Key on the DELETE (POST/PATCH-only — §10)" do
      stub_request(:delete, url("/auth/credentials/#{client_id}")).to_return(status: 204, body: "")

      resource.revoke(client_id)
      expect(a_request(:delete, url("/auth/credentials/#{client_id}"))
        .with { |req| !req.headers.key?("X-Idempotency-Key") }).to have_been_made
    end

    it "raises a typed ConflictError on a 409 (last_active_credential)" do
      stub_request(:delete, url("/auth/credentials/#{client_id}"))
        .to_return(status: 409, body: JSON.generate(
          type: "https://docs.dinie.com/errors/conflict", code: "last_active_credential"
        ))

      expect { resource.revoke(client_id) }.to raise_error(Dinie::ConflictError)
    end

    it "raises a typed NotFoundError on a 404 (credential_not_found)" do
      stub_request(:delete, url("/auth/credentials/dinie_ci_missing"))
        .to_return(status: 404, body: JSON.generate(type: "https://docs.dinie.com/errors/not-found"))

      expect { resource.revoke("dinie_ci_missing") }.to raise_error(Dinie::NotFoundError)
    end
  end
end

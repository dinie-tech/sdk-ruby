# frozen_string_literal: true

require_relative "../support/fake_token_manager"

# Surface tier for `client.webhook_endpoints` (architecture §14): each of the 6 methods → correct
# path/verb/body, pagination, idempotency on POST/PATCH (and its ABSENCE on DELETE), hydrate of the
# response (incl. the secret-bearing creation + rotation), typed error. Drives the REAL
# {Dinie::Internal::HttpClient} against WebMock — zero network. Conformance lives in story 012.
RSpec.describe Dinie::Resources::WebhookEndpoints do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_manager) { FakeTokenManager.new }
  let(:http) do
    Dinie::Internal::HttpClient.new(token_manager: token_manager, base_url: base_url, sleeper: ->(_seconds) {})
  end
  let(:resource) { described_class.new(http) }
  let(:idempotency_key) { /\Adinie-sdk-retry-/ }
  let(:endpoint_id) { "we_#{"a" * 32}" }

  def url(path)
    "#{base_url}#{path}"
  end

  # A complete `WebhookEndpoint` wire object (every required field; optionally the creation secret).
  def endpoint_wire(id:, secret: nil)
    base = {
      id: id, url: "https://partner.example.com/webhooks", events: ["loan.*"],
      description: "Production webhook", status: "active",
      created_at: 1_700_000_000, updated_at: 1_700_000_100
    }
    secret.nil? ? base : base.merge(secret: secret)
  end

  describe "#create" do
    it "POSTs /webhooks/endpoints with an alphabetical body and hydrates a WebhookEndpointWithSecret" do
      stub_request(:post, url("/webhooks/endpoints"))
        .to_return(status: 201, body: JSON.generate(endpoint_wire(id: endpoint_id, secret: "whsec_abc123")))

      created = resource.create(url: "https://partner.example.com/webhooks", events: ["loan.*"])

      expect(created).to be_a(Dinie::WebhookEndpointWithSecret)
      expect(created.secret).to eq("whsec_abc123")
      expect(a_request(:post, url("/webhooks/endpoints"))
        .with(body: { events: ["loan.*"], url: "https://partner.example.com/webhooks" })).to have_been_made
    end

    it "carries an auto X-Idempotency-Key on the POST (architecture §10)" do
      stub_request(:post, url("/webhooks/endpoints"))
        .to_return(status: 201, body: JSON.generate(endpoint_wire(id: endpoint_id, secret: "s")))

      resource.create(url: "https://partner.example.com/webhooks")
      expect(a_request(:post, url("/webhooks/endpoints"))
        .with(headers: { "X-Idempotency-Key" => idempotency_key })).to have_been_made
    end
  end

  describe "#list" do
    it "GETs /webhooks/endpoints and hydrates a Page of WebhookEndpoint (no secret)" do
      stub_request(:get, url("/webhooks/endpoints"))
        .to_return(status: 200, body: JSON.generate(data: [endpoint_wire(id: endpoint_id)], has_more: false))

      page = resource.list
      expect(page).to be_a(Dinie::Page)
      expect(page.data.map(&:class)).to eq([Dinie::WebhookEndpoint])
      expect(page.data.first.url).to eq("https://partner.example.com/webhooks")
    end

    it "passes limit and starting_after as query params, dropping omitted ones" do
      stub_request(:get, url("/webhooks/endpoints"))
        .with(query: { limit: "10", starting_after: endpoint_id })
        .to_return(status: 200, body: JSON.generate(data: [], has_more: false))

      resource.list(limit: 10, starting_after: endpoint_id)
      expect(a_request(:get, url("/webhooks/endpoints"))
        .with(query: { limit: "10", starting_after: endpoint_id })).to have_been_made
    end
  end

  describe "#retrieve" do
    it "GETs /webhooks/endpoints/{id} and hydrates a WebhookEndpoint" do
      stub_request(:get, url("/webhooks/endpoints/#{endpoint_id}"))
        .to_return(status: 200, body: JSON.generate(endpoint_wire(id: endpoint_id)))

      endpoint = resource.retrieve(endpoint_id)
      expect(endpoint).to be_a(Dinie::WebhookEndpoint)
      expect(endpoint.status).to eq("active")
    end

    it "raises a typed NotFoundError on a 404" do
      stub_request(:get, url("/webhooks/endpoints/we_missing"))
        .to_return(status: 404, body: JSON.generate(type: "https://docs.dinie.com/errors/not-found"))

      expect { resource.retrieve("we_missing") }.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "#update" do
    it "PATCHes /webhooks/endpoints/{id} with only the set keys and hydrates a WebhookEndpoint" do
      stub_request(:patch, url("/webhooks/endpoints/#{endpoint_id}"))
        .to_return(status: 200, body: JSON.generate(endpoint_wire(id: endpoint_id).merge(status: "disabled")))

      endpoint = resource.update(endpoint_id, status: "disabled")
      expect(endpoint).to be_a(Dinie::WebhookEndpoint)
      expect(endpoint.status).to eq("disabled")
      expect(a_request(:patch, url("/webhooks/endpoints/#{endpoint_id}"))
        .with(body: { status: "disabled" })).to have_been_made
    end

    it "carries an auto X-Idempotency-Key on the PATCH (architecture §10)" do
      stub_request(:patch, url("/webhooks/endpoints/#{endpoint_id}"))
        .to_return(status: 200, body: JSON.generate(endpoint_wire(id: endpoint_id)))

      resource.update(endpoint_id, description: "new desc")
      expect(a_request(:patch, url("/webhooks/endpoints/#{endpoint_id}"))
        .with(headers: { "X-Idempotency-Key" => idempotency_key })).to have_been_made
    end
  end

  describe "#delete" do
    it "DELETEs /webhooks/endpoints/{id} and returns nil (204)" do
      stub_request(:delete, url("/webhooks/endpoints/#{endpoint_id}")).to_return(status: 204, body: "")

      expect(resource.delete(endpoint_id)).to be_nil
      expect(a_request(:delete, url("/webhooks/endpoints/#{endpoint_id}"))).to have_been_made
    end

    it "does NOT carry an auto X-Idempotency-Key on the DELETE (POST/PATCH-only — §10)" do
      stub_request(:delete, url("/webhooks/endpoints/#{endpoint_id}")).to_return(status: 204, body: "")

      resource.delete(endpoint_id)
      expect(a_request(:delete, url("/webhooks/endpoints/#{endpoint_id}"))
        .with { |req| !req.headers.key?("X-Idempotency-Key") }).to have_been_made
    end
  end

  describe "#rotate_secret" do
    let(:rotation_wire) do
      { id: endpoint_id, secret: "whsec_new456", previous_secret_expires_at: 1_700_003_600 }
    end

    it "POSTs /webhooks/endpoints/{id}/rotate-secret and hydrates a WebhookSecretRotation" do
      stub_request(:post, url("/webhooks/endpoints/#{endpoint_id}/rotate-secret"))
        .to_return(status: 200, body: JSON.generate(rotation_wire))

      rotation = resource.rotate_secret(endpoint_id, expire_current_in: 7_200)

      expect(rotation).to be_a(Dinie::WebhookSecretRotation)
      expect(rotation.secret).to eq("whsec_new456")
      expect(rotation.previous_secret_expires_at).to eq(1_700_003_600)
      expect(a_request(:post, url("/webhooks/endpoints/#{endpoint_id}/rotate-secret"))
        .with(body: { expire_current_in: 7_200 })).to have_been_made
    end

    it "sends an empty body (server default grace) when expire_current_in is omitted, with an idem key" do
      stub_request(:post, url("/webhooks/endpoints/#{endpoint_id}/rotate-secret"))
        .to_return(status: 200, body: JSON.generate(rotation_wire))

      resource.rotate_secret(endpoint_id)
      expect(a_request(:post, url("/webhooks/endpoints/#{endpoint_id}/rotate-secret"))
        .with(body: "{}", headers: { "X-Idempotency-Key" => idempotency_key })).to have_been_made
    end
  end

  describe "(de)serialization round-trips" do
    it "serialize_create omits absent optionals, keeps url, alphabetical" do
      body = Dinie::WebhookEndpoint.serialize_create(url: "https://x.test/hook")
      expect(body).to eq(url: "https://x.test/hook")

      full = Dinie::WebhookEndpoint.serialize_create(
        url: "https://x.test/hook", events: ["loan.*"], description: "d"
      )
      expect(full.keys).to eq(%i[description events url])
    end

    it "serialize_update emits only the set keys (PATCH subset), alphabetical" do
      expect(Dinie::WebhookEndpoint.serialize_update(status: "disabled")).to eq(status: "disabled")
      expect(Dinie::WebhookEndpoint.serialize_update(url: "https://x.test", events: []).keys)
        .to eq(%i[events url])
      expect(Dinie::WebhookEndpoint.serialize_update).to eq({})
    end

    it "serialize_rotate_secret omits the field when absent, emits it when set" do
      expect(Dinie::WebhookSecretRotation.serialize_rotate_secret).to eq({})
      expect(Dinie::WebhookSecretRotation.serialize_rotate_secret(expire_current_in: 3_600))
        .to eq(expire_current_in: 3_600)
    end

    it "deserialize hydrates WebhookEndpointWithSecret with R-ORDER to_h incl. secret, epoch Integers" do
      wire = endpoint_wire(id: endpoint_id, secret: "whsec_abc")
      ep = Dinie::WebhookEndpointWithSecret.deserialize(wire)
      expect(ep.created_at).to be_a(Integer)
      expect(ep.events).to eq(["loan.*"])
      expect(ep.to_h.keys).to eq(%i[created_at description events id status updated_at url secret])
    end

    it "redacts the secret in inspect (PII safety)" do
      ep = Dinie::WebhookEndpointWithSecret.deserialize(endpoint_wire(id: endpoint_id, secret: "whsec_abc"))
      expect(ep.inspect).to include("secret=[REDACTED]")
      expect(ep.inspect).not_to include("whsec_abc")
    end
  end
end

# frozen_string_literal: true

require "json"

RSpec.describe "Dinie error model" do
  describe "hierarchy" do
    it "roots every error at Dinie::Error < StandardError" do
      expect(Dinie::Error.ancestors).to include(StandardError)
    end

    it "nests the API error tree" do
      expect(Dinie::APIError.ancestors).to include(Dinie::Error)
      expect(Dinie::APIConnectionError.ancestors).to include(Dinie::APIError)
      expect(Dinie::APITimeoutError.ancestors).to include(Dinie::APIConnectionError, Dinie::APIError)
      expect(Dinie::APIStatusError.ancestors).to include(Dinie::APIError)
    end

    it "places markers under APIStatusError" do
      [Dinie::BadRequestError, Dinie::AuthError, Dinie::PermissionError, Dinie::NotFoundError,
       Dinie::ConflictError, Dinie::ValidationError, Dinie::RateLimitError, Dinie::ServerError].each do |klass|
        expect(klass.ancestors).to include(Dinie::APIStatusError), "#{klass} should extend APIStatusError"
      end
    end

    it "keeps client-side errors outside the APIError tree" do
      [Dinie::OAuthError, Dinie::WebhookSignatureError, Dinie::WebhookTimestampError,
       Dinie::UnknownWebhookEventError].each do |klass|
        expect(klass.ancestors).to include(Dinie::Error)
        expect(klass.ancestors).not_to include(Dinie::APIError)
      end
    end
  end

  describe "client-side errors" do
    it "are instantiable" do
      expect(Dinie::OAuthError.new("token refresh failed")).to be_a(Dinie::Error)
      expect(Dinie::WebhookSignatureError.new).to be_a(Dinie::Error)
      expect(Dinie::WebhookTimestampError.new).to be_a(Dinie::Error)
    end

    it "preserves the event_type on UnknownWebhookEventError" do
      err = Dinie::UnknownWebhookEventError.new("loan.exploded")
      expect(err.event_type).to eq("loan.exploded")
      expect(err.message).to include('"loan.exploded"')
    end
  end

  describe Dinie::Internal::ERROR_REGISTRY do
    it "maps all 7 contract type URLs to markers" do
      expect(described_class[:by_type]).to eq(
        "https://docs.dinie.com/errors/invalid-request" => Dinie::BadRequestError,
        "https://docs.dinie.com/errors/authentication-failed" => Dinie::AuthError,
        "https://docs.dinie.com/errors/not-found" => Dinie::NotFoundError,
        "https://docs.dinie.com/errors/conflict" => Dinie::ConflictError,
        "https://docs.dinie.com/errors/validation-failed" => Dinie::ValidationError,
        "https://docs.dinie.com/errors/rate-limit-exceeded" => Dinie::RateLimitError,
        "https://docs.dinie.com/errors/internal" => Dinie::ServerError
      )
    end

    it "covers all 8 markers by status" do
      expect(described_class[:by_status]).to eq(
        400 => Dinie::BadRequestError, 401 => Dinie::AuthError, 403 => Dinie::PermissionError,
        404 => Dinie::NotFoundError, 409 => Dinie::ConflictError, 422 => Dinie::ValidationError,
        429 => Dinie::RateLimitError, 500 => Dinie::ServerError, 503 => Dinie::ServerError
      )
    end

    it "falls back to ServerError for the >=500 band" do
      expect(described_class[:fallback_5xx]).to eq(Dinie::ServerError)
    end

    it "leaves PermissionError out of by_type (P1 orphan-URL debt)" do
      expect(described_class[:by_type].values).not_to include(Dinie::PermissionError)
      expect(described_class[:by_status][403]).to eq(Dinie::PermissionError)
    end

    it "is frozen end to end" do
      expect(described_class).to be_frozen
      expect(described_class[:by_type]).to be_frozen
      expect(described_class[:by_status]).to be_frozen
    end
  end

  describe Dinie::Internal::Errors, ".from_response" do
    def problem_body(overrides = {})
      JSON.generate({ type: "https://docs.dinie.com/errors/invalid-request",
                      title: "Invalid request", status: 400 }.merge(overrides))
    end

    context "dispatch by type URL" do
      {
        "https://docs.dinie.com/errors/invalid-request" => Dinie::BadRequestError,
        "https://docs.dinie.com/errors/authentication-failed" => Dinie::AuthError,
        "https://docs.dinie.com/errors/not-found" => Dinie::NotFoundError,
        "https://docs.dinie.com/errors/conflict" => Dinie::ConflictError,
        "https://docs.dinie.com/errors/validation-failed" => Dinie::ValidationError,
        "https://docs.dinie.com/errors/rate-limit-exceeded" => Dinie::RateLimitError,
        "https://docs.dinie.com/errors/internal" => Dinie::ServerError
      }.each do |url, klass|
        it "routes #{url} to #{klass}" do
          err = described_class.from_response(status: 418, headers: {}, body: problem_body(type: url))
          expect(err).to be_a(klass)
        end
      end
    end

    it "prefers the type URL over the HTTP status" do
      # A 400 carrying a validation-failed type URL must become ValidationError, not BadRequestError.
      err = described_class.from_response(
        status: 400, headers: {},
        body: problem_body(type: "https://docs.dinie.com/errors/validation-failed")
      )
      expect(err).to be_a(Dinie::ValidationError)
    end

    context "dispatch by status (no/unknown type URL)" do
      it "routes a 403 with no type to PermissionError (orphan-URL path)" do
        err = described_class.from_response(status: 403, headers: {}, body: JSON.generate({ title: "Forbidden" }))
        expect(err).to be_a(Dinie::PermissionError)
      end

      it "routes a 404 with no type to NotFoundError" do
        err = described_class.from_response(status: 404, headers: {}, body: nil)
        expect(err).to be_a(Dinie::NotFoundError)
      end

      it "ignores an unknown type URL and falls back to status" do
        err = described_class.from_response(
          status: 409, headers: {}, body: problem_body(type: "https://docs.dinie.com/errors/unheard-of")
        )
        expect(err).to be_a(Dinie::ConflictError)
      end
    end

    context ">=500 band fallback" do
      it "routes a body-less 502 to ServerError" do
        expect(described_class.from_response(status: 502, headers: {}, body: nil)).to be_a(Dinie::ServerError)
      end

      it "routes a 504 to ServerError" do
        expect(described_class.from_response(status: 504, headers: {}, body: nil)).to be_a(Dinie::ServerError)
      end

      it "routes an unmapped 4xx to a generic APIStatusError" do
        err = described_class.from_response(status: 451, headers: {}, body: nil)
        expect(err).to be_an_instance_of(Dinie::APIStatusError)
      end
    end

    context "code / request_id extraction (once, in the base)" do
      it "extracts code from the Problem Details body" do
        err = described_class.from_response(status: 400, headers: {}, body: problem_body(code: "missing_field"))
        expect(err.code).to eq("missing_field")
      end

      it "reads request_id from the x-request-id header" do
        err = described_class.from_response(status: 400, headers: { "x-request-id" => "req_123" },
                                            body: problem_body)
        expect(err.request_id).to eq("req_123")
      end

      it "looks the header up case-insensitively and unwraps arrays" do
        err = described_class.from_response(status: 400, headers: { "X-Request-Id" => %w[req_abc req_def] },
                                            body: problem_body)
        expect(err.request_id).to eq("req_abc")
      end

      it "falls back to the body request_id when no header is present" do
        err = described_class.from_response(status: 400, headers: {}, body: problem_body(request_id: "req_body"))
        expect(err.request_id).to eq("req_body")
      end

      it "prefers the header over the body request_id" do
        err = described_class.from_response(status: 400, headers: { "x-request-id" => "req_header" },
                                            body: problem_body(request_id: "req_body"))
        expect(err.request_id).to eq("req_header")
      end
    end

    context "body shapes" do
      it "exposes the parsed Problem Details and its fields" do
        err = described_class.from_response(
          status: 422, headers: {},
          body: problem_body(type: "https://docs.dinie.com/errors/validation-failed",
                             title: "Validation failed", detail: "cpf is invalid", instance: "/customers")
        )
        expect(err.body).to be_a(Hash)
        expect(err.type).to eq("https://docs.dinie.com/errors/validation-failed")
        expect(err.title).to eq("Validation failed")
        expect(err.detail).to eq("cpf is invalid")
        expect(err.instance).to eq("/customers")
      end

      it "keeps a non-JSON body as raw text with nil Problem fields" do
        err = described_class.from_response(status: 500, headers: {}, body: "upstream exploded")
        expect(err.body).to eq("upstream exploded")
        expect(err.type).to be_nil
        expect(err.code).to be_nil
      end

      it "leaves body nil when empty" do
        err = described_class.from_response(status: 500, headers: {}, body: "")
        expect(err.body).to be_nil
      end
    end

    context "message" do
      it "summarises detail and appends the request_id" do
        err = described_class.from_response(status: 422, headers: { "x-request-id" => "req_9" },
                                            body: problem_body(detail: "cpf is invalid"))
        expect(err.message).to eq("422 cpf is invalid (request_id: req_9)")
      end

      it "notes a missing body" do
        err = described_class.from_response(status: 500, headers: {}, body: nil)
        expect(err.message).to eq("500 status code (no body)")
      end
    end

    it "honors a forced constructor, skipping dispatch" do
      err = described_class.from_response(status: 401, headers: {}, body: nil, force: Dinie::AuthError)
      expect(err).to be_a(Dinie::AuthError)
    end
  end
end

RSpec.describe Dinie, ".parse_retry_after" do
  it "parses delta-seconds from a string" do
    expect(described_class.parse_retry_after("30")).to eq(30.0)
  end

  it "uses the first element of an array (repeated header)" do
    expect(described_class.parse_retry_after(%w[45 10])).to eq(45.0)
  end

  it "prefers retry-after-ms (milliseconds) over retry-after" do
    expect(described_class.parse_retry_after("30", retry_after_ms: "1500")).to eq(1.5)
  end

  it "parses retry-after-ms on its own" do
    expect(described_class.parse_retry_after(nil, retry_after_ms: "2500")).to eq(2.5)
  end

  it "caps delta-seconds at 60" do
    expect(described_class.parse_retry_after("120")).to eq(60.0)
  end

  it "caps retry-after-ms at 60s" do
    expect(described_class.parse_retry_after(nil, retry_after_ms: "120000")).to eq(60.0)
  end

  context "HTTP-date form" do
    let(:now) { Time.utc(2026, 6, 2, 12, 0, 0) }

    before { allow(Time).to receive(:now).and_return(now) }

    it "returns the delta from now for a future date" do
      expect(described_class.parse_retry_after((now + 30).httpdate)).to be_within(0.01).of(30)
    end

    it "clamps a past date to 0" do
      expect(described_class.parse_retry_after((now - 30).httpdate)).to eq(0.0)
    end

    it "caps a far-future date at 60" do
      expect(described_class.parse_retry_after((now + 3600).httpdate)).to eq(60.0)
    end
  end

  it "returns nil for absent or unparseable input" do
    expect(described_class.parse_retry_after(nil)).to be_nil
    expect(described_class.parse_retry_after("")).to be_nil
    expect(described_class.parse_retry_after("   ")).to be_nil
    expect(described_class.parse_retry_after("not-a-date")).to be_nil
  end
end

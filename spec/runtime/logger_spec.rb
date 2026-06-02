# frozen_string_literal: true

require "set"
require "base64"
require "faraday"

# Minimal sink that records every emitted line so specs can assert on level + content.
class RecordingLogger
  Entry = Struct.new(:level, :message)

  def initialize
    @entries = []
  end

  attr_reader :entries

  def error(message) = @entries << Entry.new(:error, message)
  def warn(message) = @entries << Entry.new(:warn, message)
  def info(message) = @entries << Entry.new(:info, message)
  def debug(message) = @entries << Entry.new(:debug, message)

  def messages = @entries.map(&:message)
end

RSpec.describe Dinie::Internal::RuntimeLogger do
  describe "level resolution" do
    it "lets an explicit level win over DINIE_LOG" do
      expect(described_class.new(level: :warn, env: "debug").level).to eq(:warn)
    end

    it "falls back to DINIE_LOG when no explicit level is given" do
      expect(described_class.new(env: "info").level).to eq(:info)
    end

    it "accepts a String level and trims env whitespace" do
      expect(described_class.new(level: "debug").level).to eq(:debug)
      expect(described_class.new(env: "  warn  ").level).to eq(:warn)
    end

    it "degrades a garbage DINIE_LOG to :off (never raises)" do
      expect(described_class.new(env: "verbose").level).to eq(:off)
    end

    it "defaults to :off" do
      expect(described_class.new(env: nil).level).to eq(:off)
    end
  end

  describe "level gating (emits when level <= configured)" do
    {
      off: [],
      error: %i[error],
      warn: %i[error warn],
      info: %i[error warn info],
      debug: %i[error warn info debug]
    }.each do |configured, emitting|
      it "at #{configured} emits #{emitting.inspect} and silences the rest" do
        recorder = RecordingLogger.new
        logger = described_class.new(level: configured, logger: recorder, env: nil)
        %i[error warn info debug].each { |lvl| logger.public_send(lvl, "msg") }
        expect(recorder.entries.map(&:level)).to eq(emitting)
      end
    end
  end
end

RSpec.describe Dinie::Internal::LogRedaction do
  describe ".redact_headers" do
    it "masks every sensitive header (case-insensitive) and leaves the rest" do
      headers = {
        "Authorization" => "Bearer t", "Webhook-Signature" => "v1,x",
        "X-Dinie-Client-Secret" => "s", "Proxy-Authorization" => "p",
        "Accept" => "application/json"
      }
      expect(described_class.redact_headers(headers)).to eq(
        "Authorization" => "[REDACTED]", "Webhook-Signature" => "[REDACTED]",
        "X-Dinie-Client-Secret" => "[REDACTED]", "Proxy-Authorization" => "[REDACTED]",
        "Accept" => "application/json"
      )
    end

    it "returns {} for nil headers" do
      expect(described_class.redact_headers(nil)).to eq({})
    end
  end

  describe ".redact_body" do
    it "masks every PII field recursively (nested hashes + arrays), keeping the rest" do
      body = {
        "name" => "Ana", "cpf" => "111", "cnpj" => "222", "account" => "333", "cvv" => "444",
        "password" => "p", "secret" => "s", "client_secret" => "cs", "access_token" => "at",
        "phone" => "+55", "nested" => { "cpf" => "555", "ok" => "keep" },
        "list" => [{ "phone" => "+1" }, { "ok" => "keep" }]
      }
      out = described_class.redact_body(body)
      %w[cpf cnpj account cvv password secret client_secret access_token phone].each do |field|
        expect(out[field]).to eq("[REDACTED]")
      end
      expect(out["name"]).to eq("Ana")
      expect(out["nested"]).to eq("cpf" => "[REDACTED]", "ok" => "keep")
      expect(out["list"]).to eq([{ "phone" => "[REDACTED]" }, { "ok" => "keep" }])
    end

    it "redacts symbol keys too (case-insensitive)" do
      expect(described_class.redact_body(cpf: "1", Name: "Ana")).to eq(cpf: "[REDACTED]", Name: "Ana")
    end

    it "keeps the body-field set in lockstep with the model's canonical REDACTED_ATTRIBUTES" do
      expect(described_class::REDACTED_BODY_FIELDS)
        .to eq(Set.new(Dinie::Internal::Model::REDACTED_ATTRIBUTES.map(&:to_s)))
    end
  end

  describe ".truncate_body" do
    it "leaves a body under 2KB unchanged" do
      text = "a" * 100
      expect(described_class.truncate_body(text)).to eq(text)
    end

    it "truncates a body >= 2KB and appends the full byte size" do
      out = described_class.truncate_body("a" * 3000)
      expect(out).to start_with("a" * 2048)
      expect(out).to match(/…\[truncated, full_size=3000\]\z/)
    end

    it "truncates on a codepoint boundary (never a partial multibyte char)" do
      out = described_class.truncate_body("é" * 2000) # 2 bytes each → 4000 bytes
      body = out.sub(/…\[truncated.*\z/, "")
      expect(body.bytesize).to be <= 2048
      expect(body).to eq("é" * 1024)
      expect(out).to match(/full_size=4000\]\z/)
    end
  end

  describe ".format_body" do
    it "parses, redacts, and re-serializes a JSON string body" do
      expect(described_class.format_body('{"cpf":"111","name":"Ana"}'))
        .to eq('{"cpf":"[REDACTED]","name":"Ana"}')
    end

    it "redacts a Hash body" do
      expect(described_class.format_body({ "phone" => "+55", "ok" => 1 }))
        .to eq('{"phone":"[REDACTED]","ok":1}')
    end

    it "logs a non-JSON string body verbatim (e.g. the form-encoded token grant)" do
      expect(described_class.format_body("grant_type=client_credentials"))
        .to eq("grant_type=client_credentials")
    end

    it "returns nil for nil/empty bodies" do
      expect(described_class.format_body(nil)).to be_nil
      expect(described_class.format_body("")).to be_nil
    end
  end
end

RSpec.describe Dinie::Internal::Middleware::Logging do
  let(:recorder) { RecordingLogger.new }

  def build_connection(level)
    Faraday.new(url: "https://api.dinie.test") do |faraday|
      faraday.use described_class, level: level, logger: recorder
      faraday.adapter :test do |stub|
        stub.post("/customers") do |_env|
          [200, { "x-request-id" => "req_server_1" }, '{"id":"cust_1","cpf":"99988877766"}']
        end
        stub.get("/x") { |_env| [200, {}, "{}"] }
      end
    end
  end

  def request_line
    recorder.messages.find { |message| message.include?("→ request") }
  end

  def response_line
    recorder.messages.find { |message| message.include?("← response") }
  end

  it "logs both the request and the response at debug" do
    build_connection(:debug).post("/customers", "{}", "content-type" => "application/json")
    expect(request_line).not_to be_nil
    expect(response_line).not_to be_nil
  end

  it "emits nothing below debug" do
    build_connection(:info).get("/x")
    expect(recorder.messages).to be_empty
  end

  it "emits nothing at :off" do
    build_connection(:off).get("/x")
    expect(recorder.messages).to be_empty
  end

  it "redacts the Authorization header on the request line" do
    build_connection(:debug).post("/customers", "{}", "authorization" => "Bearer super-secret")
    expect(request_line).to include("[REDACTED]")
    expect(request_line).not_to include("super-secret")
  end

  it "redacts body PII on both the request and the response lines" do
    build_connection(:debug).post("/customers", '{"cpf":"12345678900"}', "content-type" => "application/json")
    expect(request_line).to include('"cpf":"[REDACTED]"')
    expect(request_line).not_to include("12345678900")
    expect(response_line).to include('"cpf":"[REDACTED]"')
    expect(response_line).not_to include("99988877766")
  end

  it "reports the status, the duration, and the response X-Request-Id" do
    build_connection(:debug).post("/customers", "{}", "content-type" => "application/json")
    expect(response_line).to match(/status=200/)
    expect(response_line).to match(/duration_ms=[\d.]+/)
    expect(response_line).to include("request_id=req_server_1")
  end

  it "tags a fresh request_log_id and no retry_of on a first attempt" do
    build_connection(:debug).get("/x")
    expect(request_line).to match(/request_log_id=req_[0-9a-f]+/)
    expect(request_line).not_to include("retry_of")
  end

  it "correlates a retry back to its origin via retry_of (X-Dinie-Retry-Count)" do
    connection = build_connection(:debug)
    connection.get("/x") # first attempt — stashes the origin id
    connection.get("/x") { |req| req.headers["x-dinie-retry-count"] = "1" }
    requests = recorder.messages.select { |message| message.include?("→ request") }
    origin = requests[0][/request_log_id=(req_[0-9a-f]+)/, 1]
    retried = requests[1][/retry_of=(req_[0-9a-f]+)/, 1]
    expect(retried).to eq(origin)
  end
end

RSpec.describe "logging middleware mounted on the Dinie::Client shared connection" do
  let(:recorder) { RecordingLogger.new }
  let(:base_url) { "https://api.dinie.test/api/v3" }

  before do
    stub_request(:post, "#{base_url}/auth/token")
      .to_return(status: 200, body: '{"access_token":"tok-abc","token_type":"bearer","expires_in":3600}')
    stub_request(:get, "#{base_url}/customers").to_return(status: 200, body: '{"data":[],"has_more":false}')
  end

  def make_request
    client = Dinie::Client.new(client_id: "id", client_secret: "sshh", base_url: base_url,
                               log_level: :debug, logger: recorder)
    client.instance_variable_get(:@http).request(method: :get, path: "/customers")
  end

  it "logs the token POST and the resource GET through the one shared, logged connection" do
    make_request
    requests = recorder.messages.grep(/→ request/)
    expect(requests).to include(a_string_matching(%r{POST.*/auth/token}))
    expect(requests).to include(a_string_matching(%r{GET.*/customers}))
  end

  it "redacts the token POST's Authorization: Basic (the client secret) at the seam" do
    make_request
    token_line = recorder.messages.grep(/→ request/).find { |message| message.include?("/auth/token") }
    expect(token_line).to include("[REDACTED]")
    expect(token_line).not_to include(Base64.strict_encode64("id:sshh"))
  end
end

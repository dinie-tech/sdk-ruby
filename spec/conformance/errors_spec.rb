# frozen_string_literal: true

require "json"
require_relative "loader"

# Conformance · errors — proves the RFC 9457 problem+json examples in the contract dispatch to the
# right typed error class with the right `status`/`type`/`code`/`request_id` (story 012,
# architecture §14, §6/§7). Data-driven over every `application/problem+json` example the loader
# finds; each DISTINCT payload becomes one `it` case (the contract reuses the same shapes — the
# shared `RateLimited`/`InternalError`/`BearerTokenUnauthorized` responses — across dozens of
# operations, so we dedupe by payload and log how many raw occurrences collapsed: distinct signal,
# no silent truncation). The Ruby analogue of `sdk-js` `tests/conformance/errors.test.ts`.
#
# ── How the round-trip works for errors ──
# Build a synthetic HTTP error response (status = the example's `status`, an injected `x-request-id`
# header, body = the example JSON serialized to a string) and run it through the SAME entry point
# the transport uses, `Dinie::Internal::Errors.from_response`. Assert:
#   • the instance is the class the `type` URL maps to (dispatch-by-type, the openapi catalog);
#   • `.status` / `.type` / `.code` echo the example (`code` is `nil` when the example omits it);
#   • `.request_id` surfaces the injected `x-request-id` header (the support-flow contract, §5/§7).
# No network, no time, no randomness — the request id is derived from the case index.
#
# ── Coverage of the 8 server-response classes (§6/§7, registry.rb) ──
# V0.5 (@3218365): All 8 type URLs now appear in the contract with examples → 8 classes covered:
# BadRequest(400), Auth(401), Permission(403), NotFound(404), Conflict(409), Validation(422),
# RateLimit(429), Server(500). The P1 orphan (403 `…/errors/forbidden`) is resolved in V0.5 (X2).
module ConformanceErrors
  module_function

  # openapi error `type` URL → the typed SDK class it must dispatch to (§6/§7, registry.rb).
  # V0.5: `forbidden` URL now wired to PermissionDeniedError (X2 — P1 resolved in @3218365).
  TYPE_URL_TO_CLASS = {
    "https://docs.dinie.com/errors/invalid-request" => Dinie::BadRequestError,
    "https://docs.dinie.com/errors/authentication-failed" => Dinie::AuthError,
    "https://docs.dinie.com/errors/forbidden" => Dinie::PermissionDeniedError,
    "https://docs.dinie.com/errors/not-found" => Dinie::NotFoundError,
    "https://docs.dinie.com/errors/conflict" => Dinie::ConflictError,
    "https://docs.dinie.com/errors/validation-failed" => Dinie::ValidationError,
    "https://docs.dinie.com/errors/rate-limit-exceeded" => Dinie::RateLimitError,
    "https://docs.dinie.com/errors/internal" => Dinie::ServerError
  }.freeze

  # V0.5: All 8 catalog classes are now covered; EXPECTED_UNCOVERED is empty.
  EXPECTED_UNCOVERED = {}.freeze

  ALL_CATALOG_CLASSES = %w[
    BadRequestError AuthError PermissionDeniedError NotFoundError
    ConflictError ValidationError RateLimitError ServerError
  ].freeze

  FORBIDDEN_TYPE_URL = "https://docs.dinie.com/errors/forbidden"

  Case = Struct.new(:label, :value, :expected_class, keyword_init: true)
  Plan = Struct.new(:cases, :problem_records, :unknown_type_urls, :covered_type_urls, keyword_init: true)

  # Dedupe problem+json examples by payload, classify each distinct payload by its `type` URL.
  def build_plan # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    problem_records = Conformance::Loader.examples.select { |record| record.media_type == "application/problem+json" }
    plan = Plan.new(cases: [], problem_records: problem_records, unknown_type_urls: [], covered_type_urls: [])

    distinct = {}
    problem_records.each do |record|
      key = JSON.generate(record.example_value)
      distinct[key] ||= record
    end

    distinct.each_value do |record|
      value = record.example_value
      expected = TYPE_URL_TO_CLASS[value["type"]]
      if expected.nil?
        plan.unknown_type_urls << { location: record.location, type: value["type"] }
        next
      end
      plan.covered_type_urls << value["type"]
      code_suffix = value["code"] ? " code=#{value["code"]}" : ""
      plan.cases << Case.new(
        label: "#{value["status"]} #{expected.name}#{code_suffix} · #{record.location} [#{record.example_key}]",
        value: value, expected_class: expected
      )
    end

    plan
  end
end

ERROR_PLAN = ConformanceErrors.build_plan

# ── The data-driven suite ────────────────────────────────────────────────────────────────────
RSpec.describe "conformance · problem+json → typed error class" do
  it "found problem+json examples across the catalog" do
    expect(ERROR_PLAN.cases.size).to be > 0
    # A new (unmapped) error `type` URL appearing in the contract would land here.
    expect(ERROR_PLAN.unknown_type_urls).to eq([])
  end

  ERROR_PLAN.cases.each_with_index do |error_case, index|
    it(error_case.label) do
      request_id = "req_conf_#{index}_#{error_case.value["status"]}"
      error = Dinie::Internal::Errors.from_response(
        status: error_case.value["status"],
        headers: { "x-request-id" => request_id },
        body: JSON.generate(error_case.value)
      )

      expect(error).to be_a(error_case.expected_class)
      expect(error).to be_a(Dinie::APIStatusError)
      expect(error.status).to eq(error_case.value["status"])
      expect(error.type).to eq(error_case.value["type"])
      expect(error.code).to eq(error_case.value["code"]) # nil when the example omits `code`
      expect(error.request_id).to eq(request_id)
    end
  end
end

# ── Coverage gate ──────────────────────────────────────────────────────────────────────────────
RSpec.describe "conformance · errors coverage gate" do
  # V0.5 (@3218365): all 8 catalog classes are covered — PermissionDeniedError P1 orphan resolved (X2).
  it "covers every catalog class by an example (V0.5: all 8 including PermissionDeniedError)" do
    covered = ConformanceErrors::TYPE_URL_TO_CLASS.each_with_object([]) do |(type_url, klass), acc|
      acc << klass.name.split("::").last if ERROR_PLAN.covered_type_urls.include?(type_url)
    end

    missing = ConformanceErrors::ALL_CATALOG_CLASSES.reject do |name|
      covered.include?(name) || ConformanceErrors::EXPECTED_UNCOVERED.key?(name)
    end

    puts [
      "── conformance error coverage ──",
      "problem+json example records:            #{ERROR_PLAN.problem_records.size}",
      "distinct payloads tested:                #{ERROR_PLAN.cases.size}",
      "catalog classes covered by example:      #{covered.sort.join(", ")}",
      "catalog classes intentionally uncovered: #{ConformanceErrors::EXPECTED_UNCOVERED.keys.join(", ").then { |s| s.empty? ? "(none)" : s }}"
    ].join("\n")

    expect(missing).to eq([])
    # V0.5: PermissionDeniedError is now covered (forbidden URL present in @3218365).
    expect(ERROR_PLAN.covered_type_urls).to include(ConformanceErrors::FORBIDDEN_TYPE_URL)
  end
end

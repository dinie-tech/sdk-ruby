# frozen_string_literal: true

require_relative "loader"

# Conformance round-trip — proves the V0.3 surface implements the openapi contract on every
# whole-object `application/json` example (story 012, architecture §14). Data-driven over
# `loader.rb`: each `example` / `examples.*.value` attached to a request/response/webhook schema
# becomes one `it` case. This is the safety net that the hand-written SDK matches the SoT it was
# ported from (`openapi.yaml @ 3fcfd83`) and the reference the V0.5 generator must reproduce.
#
# ════════════════════════════════════════════════════════════════════════════════════════════
# THE ROUND-TRIP, AND WHY THE RUBY ORACLE IS (NEAR-)IDENTITY  — comparison.md (014) headline data
# ════════════════════════════════════════════════════════════════════════════════════════════
# Architecture §14 frames the check as `dump(hydrate(example)) ≈ example`. The V0.3 surface is
# deliberately ASYMMETRIC (the `customer.rb` exemplar, §6): a RESPONSE schema gets `deserialize`
# only (you never POST a whole `Customer`); a REQUEST schema gets `serialize_*` only (you never
# receive a `CreateCustomerRequest`). No schema has both halves, so we exercise the ONE real SDK
# function each schema owns, supplying the missing half with a GENERIC structural transform:
#
#   • deserialize-bearing schema (responses, events):  normalize(deserialize(example).to_h) ≈ normalize(example)
#   • serialize-bearing schema   (request bodies):      serialize(symbolize(example))        ≈ example
#
# In TS the missing half is `camelizeDeep` (snake→camel on keys) because the TS surface stores
# camelCase. In RUBY the wire is snake_case AND so is the surface (RB2 — no `*Wire` type, no casing
# (de)serializer), so the oracle is **(near-)identity**: symbolize keys + normalize, NOTHING renamed.
# That asymmetry — `camelizeDeep` (TS) vs symbolize-only (Ruby) — IS the direct evidence for the
# `comparison.md` headline "casing = SPECIFIC" (§2; story 014).
#
# ════════════════════════════════════════════════════════════════════════════════════════════
# STRUCTURAL EQUALITY — TOLERANCE RULES (documented per the story)
# ════════════════════════════════════════════════════════════════════════════════════════════
# Comparison is Ruby `Hash#==` / `Array#==` on the normalized structures. Its semantics ARE the
# tolerance:
#   1. KEY ORDER ignored — `Hash#==` compares by key/value set, not insertion order (R-ORDER emits
#      alphabetical keys while the contract examples are author-ordered; both pass).
#   2. ARRAY ORDER significant — arrays are ordered data (a list page, a `kyc[]`, CNH front/back);
#      order is part of the contract, so it is NOT relaxed.
#   3. NUMBERS compared by value. Epoch ints and `Money` floats flow through BOTH sides from the
#      same parsed token (R-EPOCH — never coerced to `Time`; `Money` stays `Float`), so they are
#      identical by construction — no float-tolerance fudge needed.
#   4. **ABSENT ≡ null on HYDRATE (the Ruby-specific normalization).** Ruby's `Model#to_h` emits
#      EVERY declared attribute, an absent optional included, as `nil` (e.g. `Customer#kyc`,
#      `CreditOffer#due_date_rule`, `LoanStatusData#error`). The SDK's read side deliberately
#      collapses absent/null (R-OPTIONAL on hydrate, `customer.rb`: "Ruby collapses absent/null on
#      reads — OMIT is a dump-side concern"). So the deserialize oracle (`normalize_read`)
#      recursively DROPS nil-valued keys on BOTH sides before comparing — `cnpj: null` and an
#      omitted `cnpj` both canonicalize away. This is sanctioned normalization, not green-washing:
#      a field the SDK RENAMES, DROPS-to-a-wrong-value, SYNTHESIZES with a non-nil value, or RETYPES
#      (epoch→Time) still diverges and FAILS — exactly the casing/missing-field/dispatch bug class
#      conformance exists to catch. The absent/null distinction the SDK DOES keep lives on the DUMP
#      side (OMIT vs explicit nil); the serialize oracle (`normalize_wire`) therefore does NOT drop
#      nils, so an explicit request `null` (e.g. `CreateCredentialRequest.expires_at: null`) must be
#      preserved by the serializer or the case fails.
#
# ════════════════════════════════════════════════════════════════════════════════════════════
# SCHEMA → SDK (DE)SERIALIZER MAPPING (the hard part — documented below)
# ════════════════════════════════════════════════════════════════════════════════════════════
# `DESERIALIZERS` / `SERIALIZERS` map an openapi schema NAME (resolved `$ref`) to the SDK callable.
# Webhook events route by the example's `type` through the SDK's own `Dinie::Events::DESERIALIZERS`.
# List/flat-list envelopes (`{data:[T], has_more?}`) reuse the element schema's deserializer per
# item. The inline rotate-secret body (no `$ref`) maps by `operationId`. Everything else with a json
# example must be in `SKIP_ALLOWLIST` with a reason — the coverage gate fails on any unmapped,
# un-allowlisted json example (no silent truncation, architecture §11).
#
# NO network, NO time, NO randomness — the case list is built in contract document order at load
# time, so iteration is fully deterministic (RSpec may shuffle the resulting `it`s; each is
# independent).
module ConformanceRoundTrip # rubocop:disable Metrics/ModuleLength
  module_function

  # ── The oracle (near-identity; see the file header) ──────────────────────────────────────────

  # HYDRATE oracle: Model/Hash/Array -> plain symbol-keyed structure, recursively DROPPING nil
  # values (absent ≡ null on the Ruby read side, R-OPTIONAL on hydrate). Used for response/event
  # round-trips on BOTH the deserialized output and the contract example.
  def normalize_read(value)
    case value
    when Dinie::Internal::Model then normalize_read(value.to_h)
    when Hash
      value.each_with_object({}) do |(key, val), acc|
        normalized = normalize_read(val)
        acc[key.to_sym] = normalized unless normalized.nil?
      end
    when Array then value.map { |item| normalize_read(item) }
    else value
    end
  end

  # DUMP oracle: symbolize keys recursively, KEEPING nils (the dump side preserves explicit null vs
  # OMIT). Used for request round-trips on the serializer output and the contract example.
  def normalize_wire(value)
    case value
    when Dinie::Internal::Model then normalize_wire(value.to_h)
    when Hash then value.to_h { |key, val| [key.to_sym, normalize_wire(val)] }
    when Array then value.map { |item| normalize_wire(item) }
    else value
    end
  end

  # ── Mapping registries (openapi schema name -> SDK callable) ─────────────────────────────────

  # Response/event read models -> their `deserialize` (the hydrate half). Keyed by openapi schema
  # name; note `KycAttachmentResponse` -> `Dinie::Kyc::AttachmentResponse` and the discriminated
  # `KycRequirement` -> the value-dispatch `Dinie::Kyc.deserialize_requirement` (§6.3 hotspot).
  DESERIALIZERS = {
    "Bank" => ->(wire) { Dinie::Bank.deserialize(wire) },
    "BiometricsSession" => ->(wire) { Dinie::BiometricsSession.deserialize(wire) },
    "Credential" => ->(wire) { Dinie::Credential.deserialize(wire) },
    "CredentialWithSecret" => ->(wire) { Dinie::CredentialWithSecret.deserialize(wire) },
    "CreditOffer" => ->(wire) { Dinie::CreditOffer.deserialize(wire) },
    "Customer" => ->(wire) { Dinie::Customer.deserialize(wire) },
    "CustomerBankAccount" => ->(wire) { Dinie::CustomerBankAccount.deserialize(wire) },
    "KycAttachmentResponse" => ->(wire) { Dinie::KycAttachmentResponse.deserialize(wire) },
    "KycRequirement" => ->(wire) { Dinie.deserialize_kyc_requirement(wire) },
    "Loan" => ->(wire) { Dinie::Loan.deserialize(wire) },
    "Simulation" => ->(wire) { Dinie::Simulation.deserialize(wire) },
    "Transaction" => ->(wire) { Dinie::Transaction.deserialize(wire) },
    "WebhookEndpoint" => ->(wire) { Dinie::WebhookEndpoint.deserialize(wire) },
    "WebhookEndpointWithSecret" => ->(wire) { Dinie::WebhookEndpointWithSecret.deserialize(wire) },
    "WebhookSecretRotation" => ->(wire) { Dinie::WebhookSecretRotation.deserialize(wire) }
  }.freeze

  # Request bodies -> their `serialize_*` (the dump half). Called with the example's keys as kwargs
  # (snake = snake, so the example IS the kwargs); an example key the serializer does not accept
  # raises ArgumentError, surfaced as a clear failure (a real request-surface conformance signal).
  SERIALIZERS = {
    "CreateCredentialRequest" => ->(kwargs) { Dinie::Credential.serialize_create(**kwargs) },
    "CreateCustomerRequest" => ->(kwargs) { Dinie::Customer.serialize_create(**kwargs) },
    "CreateLoanRequest" => ->(kwargs) { Dinie::Loan.serialize_create(**kwargs) },
    # V0.5: method renamed to serialize_create_simulation (explicit verb — no ambiguity).
    "CreateSimulationRequest" => ->(kwargs) { Dinie::Simulation.serialize_create_simulation(**kwargs) },
    "CreateWebhookEndpointRequest" => ->(kwargs) { Dinie::WebhookEndpoint.serialize_create(**kwargs) },
    "CustomerBankAccountRequest" => ->(kwargs) { Dinie::CustomerBankAccount.serialize_upsert(**kwargs) },
    "UpdateCustomerRequest" => ->(kwargs) { Dinie::Customer.serialize_update(**kwargs) },
    "UpdateWebhookEndpointRequest" => ->(kwargs) { Dinie::WebhookEndpoint.serialize_update(**kwargs) }
  }.freeze

  # Inline (anonymous-schema) request bodies, mapped by `operationId` -> serializer.
  ANON_REQUEST_BY_OP = {
    # V0.5: rotate_secret uses pass-through body — no serialize wrapper; kwargs IS the body.
    "rotateWebhookSecret" => ->(kwargs) { kwargs }
  }.freeze

  # application/json examples we deliberately do NOT round-trip, each with a reason (the coverage
  # gate consults this — anything unmapped AND not here fails the gate).
  SKIP_ALLOWLIST = {
    "TokenResponse" =>
      "Internal token endpoint — parsed by runtime/TokenManager (`createToken`), not a generated " \
      "(de)serializer; off the public SDK type surface (architecture §3.1, the one internal op)."
  }.freeze

  # The headline read models that MUST be exercised by a top-level example (sanity for the gate).
  REQUIRED_COVERED = %w[
    Customer CreditOffer Loan Simulation Transaction Credential WebhookEndpoint KycAttachmentResponse
  ].freeze

  # ── Case construction (deterministic, contract document order) ───────────────────────────────

  Case = Struct.new(:label, :schema_label, :assertion, keyword_init: true)
  Plan = Struct.new(:cases, :skipped, :unmapped, :covered_schemas, :json_records, keyword_init: true)

  # Build the round-trip plan from the loader: classify every application/json example into a case,
  # an allowlist skip, or an unmapped coverage hole. Mirrors the `sdk-js` round-trip classifier.
  def build_plan # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    json_records = Conformance::Loader.examples.select { |record| record.media_type == "application/json" }
    plan = Plan.new(cases: [], skipped: [], unmapped: [], covered_schemas: [], json_records: json_records)

    json_records.each do |record|
      schema = record.schema_name

      if record.role == :event || schema.to_s.start_with?("WebhookEvent_")
        add_event_case(plan, record, schema || "WebhookEvent")
      elsif %i[list flatlist].include?(record.container) && DESERIALIZERS.key?(schema)
        add_list_case(plan, record, schema)
      elsif record.container == :single && DESERIALIZERS.key?(schema)
        add_deserialize_case(plan, record, schema)
      elsif SERIALIZERS.key?(schema)
        add_serialize_case(plan, record, schema, SERIALIZERS.fetch(schema))
      elsif schema.nil? && record.role == :request && ANON_REQUEST_BY_OP.key?(record.operation_id)
        add_serialize_case(plan, record, "#{record.operation_id} (inline body)",
                           ANON_REQUEST_BY_OP.fetch(record.operation_id))
      elsif SKIP_ALLOWLIST.key?(schema)
        plan.skipped << { record: record, reason: SKIP_ALLOWLIST.fetch(schema) }
      else
        plan.unmapped << record
      end
    end

    plan
  end

  def label_for(record, mode, schema)
    "#{record.location} · #{mode}:#{schema} [#{record.example_key}]"
  end

  def add_event_case(plan, record, schema) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    plan.covered_schemas << schema
    example = record.example_value
    plan.cases << Case.new(
      label: label_for(record, "event", schema), schema_label: schema,
      assertion: lambda do
        type = example.is_a?(Hash) ? example["type"] : nil
        deserializer = type.is_a?(String) ? Dinie::Events::DESERIALIZERS[type] : nil
        raise "event example has unknown/absent `type`: #{type.inspect}" if deserializer.nil?

        event = deserializer.call(Conformance::Loader.deep_symbolize(example))
        expect(normalize_read(event)).to eq(normalize_read(example))
      end
    )
  end

  def add_list_case(plan, record, schema) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    plan.covered_schemas << schema
    deserializer = DESERIALIZERS.fetch(schema)
    example = record.example_value
    plan.cases << Case.new(
      label: label_for(record, record.container.to_s, schema), schema_label: schema,
      assertion: lambda do
        expect(example).to be_a(Hash)
        expect(example["data"]).to be_a(Array)
        example["data"].each do |item|
          result = deserializer.call(Conformance::Loader.deep_symbolize(item))
          expect(normalize_read(result)).to eq(normalize_read(item))
        end
      end
    )
  end

  def add_deserialize_case(plan, record, schema)
    plan.covered_schemas << schema
    deserializer = DESERIALIZERS.fetch(schema)
    example = record.example_value
    plan.cases << Case.new(
      label: label_for(record, "deserialize", schema), schema_label: schema,
      assertion: lambda do
        result = deserializer.call(Conformance::Loader.deep_symbolize(example))
        expect(normalize_read(result)).to eq(normalize_read(example))
      end
    )
  end

  def add_serialize_case(plan, record, schema, serializer) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    plan.covered_schemas << schema
    example = record.example_value
    plan.cases << Case.new(
      label: label_for(record, "serialize", schema), schema_label: schema,
      assertion: lambda do
        kwargs = Conformance::Loader.deep_symbolize(example)
        produced =
          begin
            serializer.call(kwargs)
          rescue ArgumentError => e
            raise "serializer rejected the contract example keys (#{kwargs.keys.sort.inspect}): " \
                  "#{e.message} — the request example and the SDK serializer surface disagree."
          end
        expect(normalize_wire(produced)).to eq(normalize_wire(example))
      end
    )
  end

  # Deep-collect every object carrying a string discriminator — pulls the nested KYC
  # discriminated-union instances out of customer/event/attachment examples for direct dispatch.
  def collect_by_discriminator(value, discriminator, out)
    case value
    when Array then value.each { |item| collect_by_discriminator(item, discriminator, out) }
    when Hash
      out << value if value[discriminator].is_a?(String)
      value.each_value { |child| collect_by_discriminator(child, discriminator, out) }
    end
    out
  end
end

PLAN = ConformanceRoundTrip.build_plan

# ── The data-driven suite ────────────────────────────────────────────────────────────────────
RSpec.describe "conformance · round-trip (dump(hydrate(example)) ≈ example)" do
  include ConformanceRoundTrip

  it "found a non-trivial corpus of round-trippable examples" do
    # Guards against a silently-broken loader reporting zero work (which would "pass" vacuously).
    expect(PLAN.cases.size).to be > 30
  end

  PLAN.cases.each do |test_case|
    it(test_case.label) { instance_exec(&test_case.assertion) }
  end
end

# ── KYC discriminated union (architecture §6.3 / §3.4-equiv hotspot) — dedicated conformance ────
# `KycRequirement` is the project's hardest determinism shape (`oneOf` + explicit discriminator). It
# never appears as a top-level example, but the contract embeds real instances inside the
# `KycAttachmentResponse.requirement`, `Customer.kyc[]`, and `customer.*` event `data.kyc[]`
# examples. Pull every embedded instance and round-trip it DIRECTLY through the discriminated
# dispatch `Dinie::Kyc.deserialize_requirement`, so the §6.3 dispatch is exercised first-class (and
# per variant present in the contract), not only transitively through its parents.
KYC_INSTANCES = PLAN.json_records.each_with_object([]) do |record, out|
  ConformanceRoundTrip.collect_by_discriminator(record.example_value, "requirement_type", out)
end
KYC_DISTINCT = KYC_INSTANCES.uniq.freeze
KYC_VARIANTS = KYC_DISTINCT.map { |instance| instance["requirement_type"] }.uniq.sort.freeze

RSpec.describe "conformance · KYC discriminated union (deserialize_requirement dispatch)" do
  include ConformanceRoundTrip

  it "found embedded KycRequirement instances in the contract examples" do
    expect(KYC_DISTINCT).not_to be_empty
    puts "── KYC conformance ── #{KYC_INSTANCES.size} embedded instance(s) → " \
         "#{KYC_DISTINCT.size} distinct payload(s); variants present: #{KYC_VARIANTS.join(", ")}"
  end

  KYC_DISTINCT.each do |instance|
    it "KycRequirement[#{instance["requirement_type"]}]" do
      result = Dinie.deserialize_kyc_requirement(Conformance::Loader.deep_symbolize(instance))
      expect(normalize_read(result)).to eq(normalize_read(instance))
    end
  end
end

# ── Coverage gate (architecture §11/§14: no silent truncation) ──────────────────────────────────
RSpec.describe "conformance · coverage gate" do
  it "maps every application/json example to an SDK (de)serializer or an explicit allowlist" do
    if PLAN.unmapped.any?
      lines = PLAN.unmapped.map do |record|
        "  - #{record.location} [schema=#{record.schema_name || "(inline)"} container=#{record.container}]"
      end
      raise "#{PLAN.unmapped.size} application/json example(s) have no SDK mapping and no " \
            "SKIP_ALLOWLIST reason. Map them or allowlist with a reason — do not silence:\n#{lines.join("\n")}"
    end
    expect(PLAN.unmapped).to eq([])
  end

  it "reports coverage stats and the schemas without a whole-object example (informational)" do
    all_schemas = Conformance::Loader.component_schema_names
    covered = PLAN.covered_schemas.uniq.sort
    without_examples = all_schemas.reject { |name| PLAN.covered_schemas.include?(name) }.sort

    puts [
      "── conformance round-trip coverage ──",
      "application/json example records:      #{PLAN.json_records.size}",
      "round-trip test cases:                 #{PLAN.cases.size}",
      "distinct schemas/keys covered:         #{covered.size}",
      "allowlisted (internal/off-surface):    #{PLAN.skipped.size}" \
      "#{" [#{PLAN.skipped.map { |s| s[:record].schema_name }.join(", ")}]" if PLAN.skipped.any?}",
      "component schemas total:               #{all_schemas.size}",
      "component schemas WITHOUT a whole-object example (field-level scalars only, or never",
      "  exemplified — NOT a gap, just not round-trippable; covered by per-resource unit tests):",
      "  #{without_examples.join(", ")}"
    ].join("\n")

    # The headline read models must all be exercised by a top-level example. (`KycRequirement` is
    # exercised by its own sub-suite + transitively via `KycAttachmentResponse` / customer events.)
    ConformanceRoundTrip::REQUIRED_COVERED.each do |required|
      expect(PLAN.covered_schemas).to include(required), "expected a round-trip case covering #{required}"
    end
    expect(KYC_VARIANTS).not_to be_empty
  end
end

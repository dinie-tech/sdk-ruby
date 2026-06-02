# frozen_string_literal: true

require "yaml"

# Conformance loader — reads the openapi contract (the SoT) and extracts every example attached to
# a request/response/webhook schema (story 012, architecture §14, §11). NO network, NO SDK imports:
# this module only parses YAML and walks the tree, so the round-trip + error suites can layer the
# SDK mapping on top of a contract-only view. The Ruby analogue of `sdk-js`
# `tests/conformance/loader.ts` (@ `19c9bca`).
#
# ── The pinned contract (why a vendored fixture, not the live sibling repo) ──
# The default contract is VENDORED at `spec/conformance/fixtures/openapi.yaml`, a byte-for-byte copy
# of `api-docs` `apis/openapi.yaml` @ `3fcfd83` — the freeze the V0.3 surface was hand-ported
# against (every type header cites `openapi.yaml @ 3fcfd83`). Vendoring (vs reading the sibling repo)
# makes conformance:
#   * hermetic — CI checks out ONLY this repo and runs `bundle exec rspec`; there is no `api-docs`
#     checkout to read, so the contract must travel with the SDK;
#   * deterministic + pinned — immune to `api-docs` HEAD drift (HEAD already moved past `3fcfd83`,
#     e.g. KYC `submitted_at: epoch` @3fcfd83 vs a later `submitted: boolean`), so the harness tests
#     exactly what the types were built against;
#   * network-free — the AC's "sem rede" invariant holds by construction.
# A `DINIE_OPENAPI_PATH` env var overrides the path (point it at a live `api-docs` checkout to test
# the SDK against a newer contract); the default is the pinned fixture.
#
# ── What "an example associated with a schema" means here ──
# The contract carries ~146 `example:` + ~48 `examples:` blocks, but most are FIELD-LEVEL scalars on
# individual properties (`CustomerId.example`, `email.example`) — not whole-object payloads, and not
# round-trippable through a schema (de)serializer. The round-trippable corpus is the set of
# WHOLE-OBJECT examples attached at a media-type object (`…content.<mediaType>.example` or
# `…content.<mediaType>.examples.<key>.value`), where the sibling `schema` (a `$ref`, a list
# envelope, or an inline body) names the SDK type. Those are the request bodies, success responses,
# problem+json error bodies, and the 15 webhook event payloads. Field-level scalars are out of scope
# (the coverage gate logs the schemas that never produced a whole-object example — no silent
# truncation, architecture §11).
#
# ── Resolution ──
# YAML anchors/aliases (the shared `*webhook-responses`, error responses) are resolved by the parser
# (`aliases: true`). Local JSON-pointer `$ref`s (`#/components/responses/…`,
# `#/components/examples/…`) are resolved here. There are no external `$ref`s in this single-file
# contract; an unresolvable `$ref` yields `nil` and is skipped (it surfaces as missing coverage,
# never as a silent pass).
#
# ── Dependency ──
# `yaml` (Psych) is Ruby stdlib — NO new runtime OR dev dependency (the story's "prefer no new dep"
# guidance; a full openapi parser gem would add a transitive tree for a parse + manual `$ref` walk).
module Conformance
  # Reads + flattens the openapi example corpus. Pure data; the SDK mapping lives in the specs.
  module Loader # rubocop:disable Metrics/ModuleLength
    module_function

    # Default contract location — the vendored, pinned fixture (`@ 3fcfd83`).
    DEFAULT_OPENAPI_PATH = File.expand_path("fixtures/openapi.yaml", __dir__)

    # Resolved contract path — `DINIE_OPENAPI_PATH` env override wins, else the pinned fixture.
    def openapi_path
      ENV.fetch("DINIE_OPENAPI_PATH", DEFAULT_OPENAPI_PATH)
    end

    # One whole-object example, tagged with everything the round-trip/error suites need to map it.
    #   location      human-readable origin, e.g. `POST /customers -> 201` or `webhook customer.created`
    #   operation_id  the operation's `operationId` (or nil for an inline path piece)
    #   role          :request | :response | :event
    #   status        HTTP status String for responses (`"201"`, `"400"`); nil otherwise
    #   media_type    `application/json`, `application/problem+json`, …
    #   schema_name   resolved `$ref` target (`Customer`), the list element for a `{data,has_more}`
    #                 envelope (with container :list/:flatlist), or nil for an inline/anonymous schema
    #   container     :single | :list (`{data,has_more}`) | :flatlist (`{data}` — no `has_more`, §11)
    #   example_key   `(example)` for a single `example:`, else the `examples:` map key
    #   example_value the parsed example payload (string-keyed, faithful to the wire)
    ExampleRecord = Struct.new(
      :location, :operation_id, :role, :status, :media_type, :schema_name, :container,
      :example_key, :example_value, keyword_init: true
    )

    HTTP_METHODS = %w[get put post patch delete options head].freeze

    # Every whole-object example associated with a request/response/webhook schema, in contract
    # document order (deterministic — no randomness/timestamp in the iteration, per the AC).
    def examples(path = openapi_path)
      load_spec(path)[:records]
    end

    # Names of every `components.schemas.*` entry — for the coverage gate's "schemas without a
    # whole-object example" log.
    def component_schema_names(path = openapi_path)
      schemas = dig_hash(load_spec(path)[:spec], "components", "schemas")
      schemas ? schemas.keys : []
    end

    # Recursively symbolize Hash keys (String -> Symbol), recursing arrays; values pass through.
    # Mirrors `JSON.parse(body, symbolize_names: true)` — the exact wire shape the SDK
    # (de)serializers consume, so feeding a loaded example to `deserialize` is faithful.
    def deep_symbolize(value)
      case value
      when Hash then value.to_h { |key, val| [key.to_sym, deep_symbolize(val)] }
      when Array then value.map { |item| deep_symbolize(item) }
      else value
      end
    end

    # ── Internals ────────────────────────────────────────────────────────────────────────────────

    @cache = {}

    class << self # rubocop:disable Metrics/ClassLength
      # Parse the contract once per path; cache the spec + extracted records.
      def load_spec(path)
        @cache[path] ||= begin
          raw = read_contract(path)
          spec = YAML.safe_load(raw, aliases: true)
          raise "Conformance loader parsed #{path.inspect} but it is not a YAML map." unless spec.is_a?(Hash)

          { spec: spec, records: extract_records(spec) }
        end
      end

      def read_contract(path)
        File.read(path)
      rescue SystemCallError => e
        raise "Conformance loader could not read the openapi contract at #{path.inspect} " \
              "(#{e.message}). Set DINIE_OPENAPI_PATH to a readable api-docs openapi.yaml. " \
              "(no network — read-only SoT)"
      end

      # Resolve a local JSON-pointer `$ref` against the root spec; pass non-`$ref` nodes through.
      def resolve_ref(node, spec)
        return node unless node.is_a?(Hash) && node["$ref"].is_a?(String)

        ref = node["$ref"]
        return node unless ref.start_with?("#/")

        ref[2..].split("/").reduce(spec) { |cursor, seg| cursor.is_a?(Hash) ? cursor[seg] : nil }
      end

      # Classify a media-type `schema`: a `$ref` name, a list/flat-list envelope's element, or
      # anonymous (nil). `:list` carries `has_more`; `:flatlist` is the `/banks` `{data}` envelope
      # with NO `has_more` (architecture §11 — the non-paginated platform-resource shape).
      def schema_info(schema)
        return [nil, :single] unless schema.is_a?(Hash)

        ref = schema["$ref"]
        return [last_segment(ref), :single] if ref.is_a?(String)

        data = dig_hash(schema, "properties", "data")
        item_ref = data && dig_hash(data, "items")&.fetch("$ref", nil)
        if item_ref.is_a?(String)
          return [last_segment(item_ref),
                  schema["properties"].key?("has_more") ? :list : :flatlist]
        end

        [nil, :single]
      end

      def last_segment(ref)
        seg = ref.to_s.split("/").last
        seg.nil? || seg.empty? ? nil : seg
      end

      # Pull every `example` / `examples.*.value` out of a `content` object into `records`.
      def collect_content(content, ctx, spec, records) # rubocop:disable Metrics/MethodLength
        return unless content.is_a?(Hash)

        content.each do |media_type, media|
          next unless media.is_a?(Hash)

          name, container = schema_info(media["schema"])
          each_example(media, spec) do |key, value|
            records << ExampleRecord.new(
              location: ctx[:location], operation_id: ctx[:operation_id], role: ctx[:role],
              status: ctx[:status], media_type: media_type, schema_name: name, container: container,
              example_key: key, example_value: value
            )
          end
        end
      end

      # Yield `["(example)", value]` for a single `example:` and `[key, value]` for each resolved
      # `examples:` map entry that carries a `value`.
      def each_example(media, spec)
        yield "(example)", media["example"] if media.key?("example")

        examples = media["examples"]
        return unless examples.is_a?(Hash)

        examples.each do |key, raw|
          resolved = resolve_ref(raw, spec)
          yield key, resolved["value"] if resolved.is_a?(Hash) && resolved.key?("value")
        end
      end

      # Walk paths (request bodies + every response) and webhooks (each event's requestBody).
      def extract_records(spec) # rubocop:disable Metrics/MethodLength,Metrics/AbcSize
        records = []
        each_operation(spec) do |label, operation_id, op|
          request_body = resolve_ref(op["requestBody"], spec)
          if request_body.is_a?(Hash)
            ctx = { location: "#{label} -> request", operation_id: operation_id, role: :request, status: nil }
            collect_content(request_body["content"], ctx, spec, records)
          end
          collect_responses(op["responses"], label, operation_id, spec, records)
        end
        each_webhook(spec) do |event_key, operation_id, op|
          request_body = resolve_ref(op["requestBody"], spec)
          next unless request_body.is_a?(Hash)

          ctx = { location: "webhook #{event_key}", operation_id: operation_id, role: :event, status: nil }
          collect_content(request_body["content"], ctx, spec, records)
        end
        records
      end

      def collect_responses(responses, label, operation_id, spec, records)
        return unless responses.is_a?(Hash)

        responses.each do |status, raw|
          response = resolve_ref(raw, spec)
          next unless response.is_a?(Hash)

          ctx = { location: "#{label} -> #{status}", operation_id: operation_id, role: :response, status: status.to_s }
          collect_content(response["content"], ctx, spec, records)
        end
      end

      def each_operation(spec)
        paths = spec["paths"]
        return unless paths.is_a?(Hash)

        paths.each do |path_key, path_item|
          next unless path_item.is_a?(Hash)

          HTTP_METHODS.each do |method|
            op = path_item[method]
            next unless op.is_a?(Hash)

            yield "#{method.upcase} #{path_key}", op["operationId"], op
          end
        end
      end

      def each_webhook(spec)
        webhooks = spec["webhooks"]
        return unless webhooks.is_a?(Hash)

        webhooks.each do |event_key, item|
          op = item.is_a?(Hash) ? item["post"] : nil
          yield event_key, op["operationId"], op if op.is_a?(Hash)
        end
      end

      def dig_hash(node, *keys)
        keys.reduce(node) { |cursor, key| cursor.is_a?(Hash) ? cursor[key] : nil }
      end
    end
  end
end

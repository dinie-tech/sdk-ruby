# frozen_string_literal: true

require_relative "../../runtime/model"

# `Bank` type — a bank-directory entry (architecture §3.3, §6, §11). Hand-authored in V0.3 to
# mirror future generator output; the SoT is `components.schemas.Bank` (`openapi.yaml @ 3fcfd83`).
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar). Ports `sdk-js`
# `src/generated/types/bank.ts`.
#
# ── Read-only directory → deserialize only ──
# Banks are a fixed directory the partner READS (to fill `customers.upsert_bank_account`), never
# POSTed — so there is `self.deserialize` (hydrate) but NO serializer.
#
# ── `/banks` does NOT paginate (story open question, resolved — architecture §11) ──
# The `GET /banks` `200` response schema is `{ data: Bank[] }` with ONLY `data` required — NO
# `has_more`, NO `object: 'list'`, and the operation declares NO query params. The §11
# determinism rule ("a list is paginated **iff** its envelope carries `has_more`") makes
# `banks.list` return a flat `Array<Bank>`, NOT a {Dinie::Page}. So `Bank` deliberately needs no
# `id`-as-cursor contract and no list-params type. (Contrast {Credential}/{WebhookEndpoint}, whose
# list envelopes DO carry `has_more`.)
#
# ── Field map (`components.schemas.Bank` @ 3fcfd83 — all 3 required) ──
#   display_name → String   (e.g. `"001 - Banco do Brasil"`)
#   id           → String   (COMPE bank code, e.g. `"001"` — NOT a `*_…`-prefixed resource id)
#   name         → String   (e.g. `"Banco do Brasil"`)
#
# `Bank#id` is the COMPE bank-code string (`"001"`), not one of the `*_…`-prefixed resource IDs
# (architecture §3.3), so it stays a plain `String` with no entry in `ids.rb`.
module Dinie
  # A bank available for customer bank-account submission (read-only directory entry).
  class Bank < Internal::Model
    # R-ORDER: alphabetical declaration order (== `to_h` order).
    attribute :display_name, :id, :name

    # Hydrate a wire bank (symbol-keyed Hash) into a {Bank}. Explicit per-field (R-EXPLICIT);
    # every field is required, so there are no nullable spreads.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [Bank]
    def self.deserialize(raw)
      new(
        display_name: raw[:display_name],
        id: raw[:id],
        name: raw[:name]
      )
    end
  end
end

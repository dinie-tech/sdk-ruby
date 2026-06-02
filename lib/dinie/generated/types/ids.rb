# frozen_string_literal: true

# Resource ID prefixes — the 9 prefixed string IDs of the Dinie API (architecture §3.3).
# Hand-authored in V0.3 to mirror what the generator will emit from the V3 OpenAPI `*Id`
# schemas (`openapi.yaml @ 3fcfd83`, the frozen-surface SoT; V0.5 overwrites this file).
#
# ── Light branding, by design (comparison.md axis: nominal typing available) ──
# Ruby has no zero-cost nominal typing, so each ID is a plain `String`. The prefix is part of
# the *contract*, not the *type system*: in RBS each is a doc-only alias (e.g.
# `type customer_id = String`, story 013), and the `pattern` regex below — copied verbatim
# from each `components.schemas.*Id.pattern` — is asserted in tests / the conformance harness
# (story 012), never enforced at the type level. This keeps IDs ergonomic (assignable from any
# `String`) while the real shape stays documented and test-checked.
#
# ── Patterns come from the schema, never invented ──
# The customer prefix is `cust_` (NOT `cus_` — the V0.1 sketch was wrong; architecture R2).
# {Dinie::Internal::ID_PATTERNS} lives under `Internal::` (not the frozen public surface): it
# mirrors the TS `*_ID_PATTERN` consts that stay off the partner barrel. `dlv_…` (webhook
# delivery id) has NO schema/pattern in the contract — it is a plain string on the event
# envelope (story 011), so there is deliberately no entry here.
#
# ── Field map (`components.schemas.*Id.pattern` @ 3fcfd83) ──
#   schema             → RBS alias            → prefix      → pattern
#   ApiClientId        → api_client_id        → dinie_ci_   → ^dinie_ci_[0-9a-f]{32}$
#   BankAccountId      → bank_account_id      → ba_         → ^ba_[0-9a-f]{32}$
#   CreditOfferId      → credit_offer_id      → co_         → ^co_[0-9a-f]{32}$
#   CustomerId         → customer_id          → cust_       → ^cust_[0-9a-f]{32}$  (NOT cus_)
#   EventId            → event_id             → evt_        → ^evt_[0-9a-f]{32}$
#   LoanId             → loan_id              → ln_         → ^ln_[0-9a-f]{32}$
#   SimulationId       → simulation_id        → sim_        → ^sim_[0-9a-f]{32}$
#   TransactionId      → transaction_id       → tx_         → ^tx_[0-9a-f]{32}$
#   WebhookEndpointId  → webhook_endpoint_id  → we_         → ^we_[0-9a-f]{32}$
module Dinie
  module Internal
    # ID prefix patterns, copied verbatim from each `components.schemas.*Id.pattern`
    # (`openapi.yaml @ 3fcfd83`). Keyed by the (snake_case) RBS-alias stem, alphabetical so the
    # V0.5 generator produces a minimal diff. `\A…\z` is the Ruby full-string anchor for the
    # contract's `^…$`. Used by tests and the conformance harness; NOT part of the frozen
    # public surface (hence `Internal::`).
    ID_PATTERNS = {
      api_client: /\Adinie_ci_[0-9a-f]{32}\z/,
      bank_account: /\Aba_[0-9a-f]{32}\z/,
      credit_offer: /\Aco_[0-9a-f]{32}\z/,
      customer: /\Acust_[0-9a-f]{32}\z/,
      event: /\Aevt_[0-9a-f]{32}\z/,
      loan: /\Aln_[0-9a-f]{32}\z/,
      simulation: /\Asim_[0-9a-f]{32}\z/,
      transaction: /\Atx_[0-9a-f]{32}\z/,
      webhook_endpoint: /\Awe_[0-9a-f]{32}\z/
    }.freeze
  end
end

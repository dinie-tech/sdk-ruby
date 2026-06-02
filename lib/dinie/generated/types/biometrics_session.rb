# frozen_string_literal: true

require_relative "../../runtime/model"

# `BiometricsSession` — a temporary biometrics-capture session (architecture §3.3, §6), read-only.
# Follows the hydrate/dump convention documented in `customer.rb` (THE exemplar). Hand-authored in
# V0.3 to mirror future generator output; `components.schemas.BiometricsSession`
# (`openapi.yaml @ 3fcfd83`) is the SoT.
#
# ── Read-only: deserialize only, no serializer ──
# `POST /customers/{id}/biometrics` is **body-less** in the contract (the session is minted
# server-side from the path customer), so this type has a `deserialize` (hydrate) and NO
# `serialize_*` (dump). The frozen surface confirms `createBiometricsSession` takes no params
# (`Record<string, never>`, a forward-compat seam).
#
# ── Field map (`components.schemas.BiometricsSession` @ 3fcfd83) — wire snake = surface snake ──
#   expires_at   → Integer  (epoch seconds, R-EPOCH)
#   session_url  → String   (URL the partner embeds in their flow — webview or redirect)
module Dinie
  # A biometrics capture session — the read model returned by `customers.create_biometrics_session`.
  class BiometricsSession < Internal::Model
    # R-ORDER: attributes declared alphabetically (the source-emission order IS `to_h`'s order).
    attribute :expires_at, :session_url

    # Hydrate a wire biometrics session (symbol-keyed Hash) into a {BiometricsSession}. Explicit
    # per-field (R-EXPLICIT); `expires_at` stays `Integer` (R-EPOCH).
    #
    # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
    # @return [BiometricsSession]
    def self.deserialize(raw)
      new(
        expires_at: raw[:expires_at],
        session_url: raw[:session_url]
      )
    end
  end
end

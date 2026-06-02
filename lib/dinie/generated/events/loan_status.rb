# frozen_string_literal: true

require_relative "../../runtime/model"
require_relative "base"

# `loan.finished` + `loan.cancelled` + `loan.error` events (`WebhookEvent_LoanStatus`) —
# architecture §3.1, §8. ONE openapi schema, THREE event classes (the `type` `enum`). Hand-authored
# in V0.3; ports `sdk-js` `src/generated/events/loan-status.ts` (@ `19c9bca`). DS-EVENT, multi-type.
#
# `data` ({LoanStatusData}) is the bespoke terminal-status payload (`{id, status, error?}`). The
# nested `error` is OPTIONAL on the shared schema and present only for `loan.error` — the contract
# does not split it per `type`, so it is modeled as an always-declared attribute that is `nil` when
# absent (R-OPTIONAL on hydrate), `LoanErrorDetails` when present. NOT the `Loan` read-model.
#
# ── Naming note (a Ruby-specific divergence, recorded for `comparison.md` §2.5) ──
# The golden names the nested error object `LoanError` and suffixes the event `LoanErrorEvent`. The
# Ruby surface drops the `Event` suffix on ALL members (architecture §6.3: `case event; when
# Dinie::Events::LoanError`), so the `loan.error` event IS {LoanError}. To avoid the constant
# collision the TS `Event` suffix sidesteps, the nested error object is named {LoanErrorDetails}.
module Dinie
  module Events
    # Error details, present only on `loan.error` (nested in {LoanStatusData#error}). Named
    # `LoanErrorDetails` to avoid colliding with the {LoanError} event class (see the file header).
    class LoanErrorDetails < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :code, :message

      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanErrorDetails]
      def self.deserialize(raw)
        new(
          code: raw[:code],
          message: raw[:message]
        )
      end
    end

    # Payload shared by `loan.finished`, `loan.cancelled`, and `loan.error`. `status` carries the
    # schema enum; `error` is present (a {LoanErrorDetails}) only on `loan.error`, else `nil`.
    class LoanStatusData < Internal::Model
      # R-ORDER: attributes declared alphabetically.
      attribute :error, :id, :status

      # Hydrate the shared terminal-status payload. `error` is hydrated only when present
      # (R-OPTIONAL on hydrate) — `raw[:error] && …` mirrors the KYC `submitted` convention.
      #
      # @param raw [Hash{Symbol => Object}] the wire object (snake_case keys)
      # @return [LoanStatusData]
      def self.deserialize(raw)
        new(
          error: raw[:error] && LoanErrorDetails.deserialize(raw[:error]),
          id: raw[:id],
          status: raw[:status]
        )
      end
    end

    # A verified `loan.finished` event (envelope + {LoanStatusData}).
    class LoanFinished < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanFinished]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.finished"
        )
      end
    end

    # A verified `loan.cancelled` event (envelope + {LoanStatusData}).
    class LoanCancelled < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanCancelled]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.cancelled"
        )
      end
    end

    # A verified `loan.error` event (envelope + {LoanStatusData}; `data.error` is a
    # {LoanErrorDetails}). The event class is unsuffixed (§6.3) — see the file header on the name.
    class LoanError < WebhookEventBase
      # @param raw [Hash{Symbol => Object}] the wire event
      # @return [LoanError]
      def self.deserialize(raw)
        new(
          api_version: raw[:api_version],
          created_at: raw[:created_at],
          data: LoanStatusData.deserialize(raw[:data]),
          delivery_id: raw[:delivery_id],
          id: raw[:id],
          timestamp: raw[:timestamp],
          type: "loan.error"
        )
      end
    end
  end
end

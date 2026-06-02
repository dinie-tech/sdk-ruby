# frozen_string_literal: true

require_relative "../support/webhook_event_fixtures"

# Webhook events specs (story 011 — the second V0.3 hotspot) — the 15 typed events, the bespoke
# per-event `data` payloads, and the {Dinie::Events::DESERIALIZERS} dispatch table (architecture
# §3.1, §4.1, §8; frozen surface §"15 webhook events / 11 schemas"). Companion to
# `spec/runtime/webhooks_spec.rb` (the `extract` signature matrix). Fixtures: {WebhookEventFixtures}.
#
# Conformance (story 012) proves the full example set; this story guarantees the per-type case +
# exact round-trip.
RSpec.describe Dinie::Events do
  include WebhookEventFixtures

  describe "Dinie::Events::DESERIALIZERS (the forcing-function dispatch table, §4.1)" do
    it "is frozen and holds exactly the 15 frozen event types" do
      expect(Dinie::Events::DESERIALIZERS).to be_frozen
      expect(Dinie::Events::DESERIALIZERS.size).to eq(15)
      expect(Dinie::Events::DESERIALIZERS.keys).to contain_exactly(
        "customer.created", "customer.under_review", "customer.active", "customer.denied",
        "customer.kyc_updated", "credit_offer.available", "credit_offer.expired", "loan.created",
        "loan.signature_received", "loan.processing", "loan.active", "loan.payment_received",
        "loan.finished", "loan.cancelled", "loan.error"
      )
    end

    it "covers exactly the keys the event fixtures exercise (completeness)" do
      expect(Dinie::Events::DESERIALIZERS.keys).to match_array(webhook_event_table.map { |entry| entry[:type] })
    end
  end

  describe "the 15 events — dispatch, typing, and exact round-trip" do
    it "dispatches every type to its event class (a WebhookEventBase) + bespoke data class" do
      webhook_event_table.each do |entry|
        wire = webhook_envelope(type: entry[:type], data: entry[:data])
        event = Dinie::Events::DESERIALIZERS[entry[:type]].call(wire)

        expect(event).to be_a(entry[:klass]), "expected #{entry[:type]} → #{entry[:klass]}"
        expect(event).to be_a(Dinie::Events::WebhookEventBase)
        expect(event.type).to eq(entry[:type])
        expect(event.data).to be_a(entry[:data_klass])
        expect(event.data.status).to eq(entry[:status])
      end
    end

    it "hydrates the full envelope per member (R-ORDER, R-EPOCH)" do
      entry = webhook_event_table.find { |row| row[:type] == "credit_offer.available" }
      event = Dinie::Events::CreditOfferAvailable.deserialize(webhook_envelope(type: entry[:type], data: entry[:data]))

      expect(event.api_version).to eq("2026-03-01")
      expect(event.created_at).to eq(1_772_791_200)   # epoch stays Integer (R-EPOCH)
      expect(event.delivery_id).to eq("dlv_abc123")   # plain string, no branded id
      expect(event.id).to eq("evt_550e8400e29b41d4a716446655440000")
      expect(event.timestamp).to eq(1_772_791_250)
      expect(event.to_h.keys).to eq(%i[api_version created_at data delivery_id id timestamp type])
    end

    it "round-trips every event exactly (deep_h == wire — the conformance-shape guarantee)" do
      webhook_event_table.each do |entry|
        wire = webhook_envelope(type: entry[:type], data: entry[:data])
        event = Dinie::Events::DESERIALIZERS[entry[:type]].call(wire)

        expect(deep_h(event)).to eq(wire), "round-trip mismatch for #{entry[:type]}"
      end
    end
  end

  describe "multi-type schemas (one data shape, distinct event classes — DS-EVENT)" do
    it "routes customer.under_review and customer.active to distinct classes sharing CustomerStatusData" do
      under = build_event("customer.under_review")
      active = build_event("customer.active")

      expect(under).to be_a(Dinie::Events::CustomerUnderReview)
      expect(active).to be_a(Dinie::Events::CustomerActive)
      expect(under).not_to be_a(Dinie::Events::CustomerActive)
      expect([under.data, active.data]).to all(be_a(Dinie::Events::CustomerStatusData))
    end

    it "routes the three loan-status types to distinct classes sharing LoanStatusData" do
      finished = build_event("loan.finished")
      cancelled = build_event("loan.cancelled")
      errored = build_event("loan.error")

      expect([finished, cancelled, errored].map(&:class)).to eq(
        [Dinie::Events::LoanFinished, Dinie::Events::LoanCancelled, Dinie::Events::LoanError]
      )
      expect([finished.data, cancelled.data, errored.data]).to all(be_a(Dinie::Events::LoanStatusData))
    end
  end

  describe "embedded KYC requirements (the reused discriminated union — story 009)" do
    it "hydrates customer.created data.kyc through Kyc.deserialize_requirement (by class)" do
      event = build_event("customer.created")

      expect(event.data.kyc).to all(be_a(Dinie::Kyc::Requirement))
      expect(event.data.kyc.first).to be_a(Dinie::Kyc::SelfieRequirement)
      expect(event.data.kyc.first.submitted).to be_a(Dinie::Kyc::Submitted)
    end

    it "hydrates customer.kyc_updated data.kyc the same way" do
      expect(build_event("customer.kyc_updated").data.kyc.first).to be_a(Dinie::Kyc::SelfieRequirement)
    end
  end

  describe "nested sub-objects (per-object hydrators — DS-EVENT recursion)" do
    it "hydrates loan.signature_received data.signer into a LoanSigner" do
      event = build_event("loan.signature_received")

      expect(event.data.signer).to be_a(Dinie::Events::LoanSigner)
      expect(event.data.signer.name).to eq("Ana Lima")
      expect(event.data.signer.signed_at).to eq(1_772_791_200) # epoch stays Integer
    end

    it "hydrates loan.payment_received data.payment into a LoanPayment (Money stays Float)" do
      event = build_event("loan.payment_received")

      expect(event.data.payment).to be_a(Dinie::Events::LoanPayment)
      expect(event.data.payment.amount).to eq(450.75)
      expect(event.data.payment.amount).to be_a(Float)
      expect(event.data.payment.installment_number).to eq(1)
    end

    it "hydrates loan.error data.error into a LoanErrorDetails, and leaves it nil otherwise (R-OPTIONAL)" do
      errored = build_event("loan.error")
      finished = build_event("loan.finished")

      expect(errored.data.error).to be_a(Dinie::Events::LoanErrorDetails)
      expect(errored.data.error.code).to eq("disbursement_failed")
      expect(errored.data.error.message).to eq("Bank rejected the transfer")
      expect(finished.data.error).to be_nil
    end
  end

  describe "Money fields stay Float (no wrapper — types/money.rb)" do
    it "keeps credit_offer approved_amount and loan amounts as Float" do
      offer = build_event("credit_offer.available")
      loan = build_event("loan.active")

      expect(offer.data.approved_amount).to be_a(Float).and eq(5000.0)
      expect(offer.data.min_amount).to be_a(Float)
      expect(loan.data.principal_amount).to be_a(Float).and eq(5250.5)
    end
  end

  describe "R-OPTIONAL on hydrate (absent optional → nil, key still declared)" do
    it "leaves customer.created data.cnpj nil when the wire omits it" do
      entry = webhook_event_table.find { |row| row[:type] == "customer.created" }
      data = entry[:data].except(:cnpj)
      event = Dinie::Events::CustomerCreated.deserialize(webhook_envelope(type: "customer.created", data:))

      expect(event.data.cnpj).to be_nil
      expect(event.data.to_h).to include(cnpj: nil) # always-declared (R-OPTIONAL Ruby manifestation)
    end
  end

  describe "partner discrimination by class (RB9 / §6.3) + pattern matching" do
    it "matches an event by class with case/when" do
      label = case build_event("loan.active")
              when Dinie::Events::LoanActive then :active
              when Dinie::Events::LoanCreated then :created
              end

      expect(label).to eq(:active)
    end

    it "supports deconstruct_keys for pattern matching on the envelope + data" do
      matched =
        case build_event("customer.active")
        in { type: "customer.active", data: Dinie::Events::CustomerStatusData => data }
          data.status
        end

      expect(matched).to eq("active")
    end
  end

  describe "WebhookEventBase (the shared envelope)" do
    it "is the common ancestor of every event class" do
      event_classes = webhook_event_table.map { |entry| entry[:klass] }.uniq
      expect(event_classes.size).to eq(15)
      expect(event_classes).to all(be < Dinie::Events::WebhookEventBase)
    end
  end

  # Build a verified-shaped event straight through its dispatch entry, for the per-type assertions.
  def build_event(type)
    entry = webhook_event_table.find { |row| row[:type] == type }
    Dinie::Events::DESERIALIZERS[type].call(webhook_envelope(type:, data: entry[:data]))
  end
end

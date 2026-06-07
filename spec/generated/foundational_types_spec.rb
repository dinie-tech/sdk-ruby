# frozen_string_literal: true

# Exemplar round-trip + convention specs for the foundational types (story 006). Proves the
# hydrate/dump convention 007–011 copy: explicit per-field hydrate, OMIT-vs-nil dump, epoch
# stays Integer, Money stays Float, ID prefixes, enum constants, deconstruct_keys. Values are
# taken from the `openapi.yaml @ 3fcfd83` schema examples.
RSpec.describe "foundational types" do
  # Recursively dump a hydrated model graph back to wire-shaped Hashes/Arrays/scalars, so the
  # lossless round-trip also covers the nested KYC union (`kyc` → `Kyc::*Requirement`, story 009).
  def deep_h(obj)
    case obj
    when Dinie::Internal::Model then obj.to_h.transform_values { |value| deep_h(value) }
    when Array then obj.map { |item| deep_h(item) }
    else obj
    end
  end

  let(:customer_wire) do
    {
      cnpj: "12.345.678/0001-90",
      cpf: "123.456.789-00",
      created_at: 1_700_000_000,
      email: "joao@example.com",
      external_id: "partner-ref-123",
      id: "cust_550e8400e29b41d4a716446655440000",
      kyc: [
        {
          requirement_type: "identity",
          requirement_id: "identity_003XXXXXXXXXXXXXXX",
          label: "Documento de identidade",
          mandatory: true,
          subject: { id: "003XXXXXXXXXXXXXXX", name: "Joao Silva", subject_type: "applicant" },
          submitted: {
            evidence_type: "cnh",
            attachments: [{ attachment_type: "front", submitted: true }],
            review_status: "pending",
            review_reason: nil
          }
        }
      ],
      name: "Joao Silva",
      phone: "+5511999999999",
      status: "active",
      trading_name: "Loja do Joao",
      updated_at: 1_700_000_500
    }
  end

  let(:credential_wire) do
    {
      client_id: "dinie_ci_550e8400e29b41d4a716446655440000",
      created_at: 1_700_000_000,
      expires_at: nil,
      id: "dinie_ci_550e8400e29b41d4a716446655440000",
      last_used_at: nil,
      name: "Production Key",
      status: "active",
      updated_at: 1_700_000_500
    }
  end

  let(:credit_offer_wire) do
    # V0.5: FixedInstallmentCreditOffer has `installments` but NOT `min/max_installments`
    # (those belong to RangeInstallmentCreditOffer — the DS-IMPLICIT union separates them).
    {
      approved_amount: 25_000.00,
      created_at: 1_700_000_000,
      customer_id: "cust_550e8400e29b41d4a716446655440000",
      due_date_rule: nil,
      external_id: "partner-ref-123",
      id: "co_550e8400e29b41d4a716446655440000",
      installments: 12,
      min_amount: 200.00,
      monthly_interest_rate: 3.50,
      status: "available",
      updated_at: 1_700_000_500,
      valid_until: 1_775_253_599
    }
  end

  describe "Dinie::Customer — hydrate (deserialize)" do
    subject(:customer) { Dinie::Customer.deserialize(customer_wire) }

    it "round-trips a full wire object losslessly (deep dump == wire; snake = snake, zero conversion)" do
      # `deep_h` recurses through the hydrated KYC union; `to_h` alone is shallow (kyc → objects).
      expect(deep_h(customer)).to eq(customer_wire)
    end

    it "keeps epoch timestamps as Integer (R-EPOCH — never Time)" do
      expect(customer.created_at).to be_an(Integer)
      expect(customer.updated_at).to be_an(Integer)
    end

    it "carries cpf/cnpj/email/phone and NOT tax_id (demo != contract, R1)" do
      expect([customer.cpf, customer.cnpj, customer.email, customer.phone])
        .to eq(["123.456.789-00", "12.345.678/0001-90", "joao@example.com", "+5511999999999"])
      expect(customer.to_h).not_to have_key(:tax_id)
    end

    it "hydrates kyc into the discriminated Kyc::* union (story 009)" do
      expect(customer.kyc.map(&:class)).to eq([Dinie::IdentityRequirement])
      expect(customer.kyc.first.requirement_type).to eq("identity")
      expect(customer.kyc.first.subject).to be_a(Dinie::KycSubject)
      expect(customer.kyc.first.submitted).to be_a(Dinie::Internal::Model)
    end

    it "sets an absent optional (kyc, omitted during `creating`) to nil but still declares it" do
      wire = customer_wire.except(:kyc)
      hydrated = Dinie::Customer.deserialize(wire)
      expect(hydrated.kyc).to be_nil
      expect(hydrated.to_h).to have_key(:kyc)
    end

    it "is explicit, not a blind symbolize — ignores unknown wire keys (e.g. a dropped `object`)" do
      hydrated = Dinie::Customer.deserialize(customer_wire.merge(object: "customer"))
      expect(deep_h(hydrated)).to eq(customer_wire)
    end

    it "supports pattern matching via deconstruct_keys" do
      matched =
        case customer
        in { status: "active", id: }
          id
        else
          :no_match
        end
      expect(matched).to eq("cust_550e8400e29b41d4a716446655440000")
    end
  end

  describe "Dinie::Customer — dump (serialize_create / serialize_update): OMIT vs nil (R-OPTIONAL)" do
    it "emits only the required keys, alphabetical (R-ORDER), when optionals are omitted" do
      body = Dinie::Customer.serialize_create(
        email: "joao@example.com", phone: "+5511999999999",
        cpf: "123.456.789-00", cnpj: "12.345.678/0001-90"
      )
      expect(body).to eq(
        cnpj: "12.345.678/0001-90", cpf: "123.456.789-00",
        email: "joao@example.com", phone: "+5511999999999"
      )
      expect(body.keys).to eq(%i[cnpj cpf email phone])
    end

    it "includes optionals when provided" do
      body = Dinie::Customer.serialize_create(
        email: "j@x.com", phone: "+5511999999999", cpf: "1", cnpj: "2",
        name: "Joao", external_id: "ref-1"
      )
      expect(body).to include(external_id: "ref-1", name: "Joao")
    end

    it "emits only the fields the caller set on update" do
      expect(Dinie::Customer.serialize_update(email: "new@x.com")).to eq(email: "new@x.com")
      expect(Dinie::Customer.serialize_update).to eq({})
    end
  end

  describe "Dinie::Credential / Dinie::CredentialWithSecret" do
    it "hydrates a Credential, carrying required-nullable fields as nil" do
      cred = Dinie::Credential.deserialize(credential_wire)
      expect(cred.to_h).to eq(credential_wire)
      expect(cred.expires_at).to be_nil
      expect(cred.last_used_at).to be_nil
    end

    it "hydrates CredentialWithSecret (allOf -> subclass) and IS a Credential" do
      raw = credential_wire.merge(client_secret: "dinie_cs_live_xxx")
      with_secret = Dinie::CredentialWithSecret.deserialize(raw)
      expect(with_secret).to be_a(Dinie::Credential)
      expect(with_secret.client_secret).to eq("dinie_cs_live_xxx")
      expect(with_secret.to_h).to eq(raw)
    end

    it "redacts client_secret in inspect (PII base list) without leaking the value" do
      raw = credential_wire.merge(client_secret: "dinie_cs_live_xxx")
      rendered = Dinie::CredentialWithSecret.deserialize(raw).inspect
      expect(rendered).to include("client_secret=[REDACTED]")
      expect(rendered).not_to include("dinie_cs_live_xxx")
    end

    it "dumps CreateCredentialRequest: omits expires_at on OMIT, sends an explicit nil as null" do
      expect(Dinie::Credential.serialize_create(name: "Prod")).to eq(name: "Prod")
      expect(Dinie::Credential.serialize_create(name: "Prod", expires_at: nil))
        .to eq(expires_at: nil, name: "Prod")
      expect(Dinie::Credential.serialize_create(name: "Prod", expires_at: 1_803_945_600))
        .to eq(expires_at: 1_803_945_600, name: "Prod")
    end
  end

  describe "Dinie::CreditOffer (read-only, R10)" do
    subject(:offer) { Dinie::CreditOffer.deserialize(credit_offer_wire) }

    it "round-trips a full wire object losslessly" do
      expect(offer.to_h).to eq(credit_offer_wire)
    end

    it "exposes Money (approved_amount) as a plain Float — deferred decision §21.2" do
      expect(offer.approved_amount).to be_a(Float)
      expect(offer.approved_amount).to eq(25_000.00)
    end

    it "keeps epoch fields Integer and dispatches to FixedInstallmentCreditOffer when installments is present" do
      # V0.5 DS-IMPLICIT: presence of `installments` key → FixedInstallmentCreditOffer.
      expect(offer.valid_until).to be_an(Integer)
      expect(offer).to be_a(Dinie::FixedInstallmentCreditOffer)
      expect(offer.installments).to eq(12)
      # FixedInstallmentCreditOffer has no min/max_installments (those are RangeInstallmentCreditOffer fields).
      expect(offer).not_to respond_to(:min_installments)
      expect(offer).not_to respond_to(:max_installments)
    end

    it "has no serializer (offers are minted by the Core, never POSTed)" do
      # V0.5: CreditOffer is a dispatch module; neither Fixed nor Range has a serialize_create.
      expect(Dinie::FixedInstallmentCreditOffer).not_to respond_to(:serialize_create)
      expect(Dinie::RangeInstallmentCreditOffer).not_to respond_to(:serialize_create)
    end
  end

  describe "ID prefix patterns (Dinie::Internal::ID_PATTERNS — from each schema `pattern`)" do
    it "matches the example IDs against their schema patterns" do
      expect("cust_550e8400e29b41d4a716446655440000").to match(Dinie::Internal::ID_PATTERNS[:customer])
      expect("co_550e8400e29b41d4a716446655440000").to match(Dinie::Internal::ID_PATTERNS[:credit_offer])
      # V0.5 ApiClientId pattern now requires live|test segment: dinie_ci_(live|test)_<alphanum>
      expect("dinie_ci_live_550e8400e29b41d4a716446655440000").to match(Dinie::Internal::ID_PATTERNS[:api_client])
    end

    it "rejects the wrong prefix (cus_ is NOT cust_ — architecture R2)" do
      expect("cus_550e8400e29b41d4a716446655440000").not_to match(Dinie::Internal::ID_PATTERNS[:customer])
    end
  end

  describe "enum constant modules (discoverability — values are plain String)" do
    it "exposes named constants equal to the wire values" do
      expect(Dinie::CustomerStatus::ACTIVE).to eq("active")
      expect(Dinie::CredentialStatus::REVOKED).to eq("revoked")
      # V0.5: CreditOfferStatus enum module removed (status is a plain string on the union variants).
      expect(Dinie::LoanStatus::ACTIVE).to eq("active")
    end

    it "lists every value in ALL" do
      expect(Dinie::CustomerStatus::ALL).to eq(%w[creating pending_kyc under_review active denied])
      # V0.5: CreditOfferStatus removed; verify another present enum.
      expect(Dinie::ReviewStatus::ALL).to eq(%w[pending accepted rejected])
    end
  end
end

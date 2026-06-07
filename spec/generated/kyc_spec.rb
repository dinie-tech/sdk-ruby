# frozen_string_literal: true

require "stringio"

# KYC block specs (story 009) — the project's complexity HOTSPOT and the `comparison.md` canary
# (architecture §6.3, §14 "KYC tier — exhaustive, per-variant"). Two tiers:
#
#   1. Unit (Dinie module-level)   — per-variant hydrate of the 9 `*Requirement` variants and the
#                                    DS-IMPLICIT CNH|RG identity dispatch; per-variant serialize of
#                                    the 10 upload union members to the multipart field-map; the
#                                    discriminated `case/when` dispatch (right subclass by value);
#                                    pattern matching by class + `deconstruct_keys`; unknown
#                                    discriminator → typed {Dinie::Error}; exact round-trip.
#   2. Resource (`kyc_attachments`)— the multipart `create` (201) over a real {Dinie::Client} +
#                                    WebMock, and `start_kyc_review` (202 → nil), incl. idempotency
#                                    and a typed error.
#
# V0.5 contract changes from @3fcfd83 → @3218365:
#   - All Kyc types are now directly under Dinie (no Dinie::Kyc namespace).
#   - Module-level functions: Dinie.deserialize_kyc_requirement, Dinie.deserialize_identity_submitted,
#     Dinie.serialize_kyc_upload.
#   - KycAttachment: submitted_at: Integer|nil → submitted: Boolean.
#   - KycAttachmentResponse: {id, uploaded_at, requirement} → {attachment_type, submitted}.
RSpec.describe Dinie do
  # Recursively dump a hydrated model graph back to wire-shaped Hashes/Arrays/scalars, for exact
  # round-trip assertions (the analogue of the conformance oracle, story 012).
  def deep_h(obj)
    case obj
    when Dinie::Internal::Model then obj.to_h.transform_values { |value| deep_h(value) }
    when Array then obj.map { |item| deep_h(item) }
    else obj
    end
  end

  def subject_wire(id: "003XXXXXXXXXXXXXXX")
    { id:, name: "Joao Silva", subject_type: "applicant" }
  end

  # A single-attachment `*Submitted` wire for the uniform (non-identity) variants.
  # V0.5: KycAttachment uses submitted: Boolean (not submitted_at: Integer|nil).
  def submitted_wire(evidence_type:, attachment_type: "file", review_status: "accepted", review_reason: nil)
    {
      evidence_type:,
      attachments: [{ attachment_type:, submitted: true }],
      review_status:, review_reason:
    }
  end

  # ── The nine requirement variants (discriminator `requirement_type`) ──
  # `person` ⇒ carries a `subject` (DS-SUBJECT); `evidence`/`attachment` shape the `submitted`.
  # V0.5: All Kyc classes are directly under Dinie (no Dinie::Kyc:: namespace).
  requirement_variants = [
    { type: "identity", klass: Dinie::IdentityRequirement, person: true, evidence: "cnh", attachment: "front" },
    { type: "selfie", klass: Dinie::SelfieRequirement, person: true, evidence: "selfie", attachment: "photo" },
    { type: "proof_of_address", klass: Dinie::ProofOfAddressRequirement, person: true,
      evidence: "proof_of_address", attachment: "file" },
    { type: "company_document", klass: Dinie::CompanyDocumentRequirement, person: false,
      evidence: "ccmei", attachment: "file" },
    { type: "ei_mei_documents", klass: Dinie::EiMeiDocumentsRequirement, person: false,
      evidence: "ei_mei", attachment: "ccmei" },
    { type: "income_statement", klass: Dinie::IncomeStatementRequirement, person: false,
      evidence: "income_statement", attachment: "file" },
    { type: "articles_of_association", klass: Dinie::ArticlesOfAssociationRequirement, person: false,
      evidence: "articles_of_association", attachment: "file" },
    { type: "eireli_incorporation_statement", klass: Dinie::EireliIncorporationStatementRequirement,
      person: false, evidence: "eireli_incorporation_statement", attachment: "file" },
    { type: "email", klass: Dinie::EmailRequirement, person: true, evidence: "email", attachment: "email" }
  ].freeze

  def requirement_wire(variant, with_submitted: true)
    req_id = variant[:person] ? "#{variant[:type]}_003XXXXXXXXXXXXXXX" : variant[:type]
    wire = { requirement_type: variant[:type], requirement_id: req_id, label: "Label", mandatory: true }
    wire[:subject] = subject_wire if variant[:person]
    if with_submitted
      wire[:submitted] = submitted_wire(evidence_type: variant[:evidence], attachment_type: variant[:attachment])
    end
    wire
  end

  # V0.5: function renamed to deserialize_kyc_requirement; base class is KycRequirement; subject is KycSubject.
  describe ".deserialize_kyc_requirement (DS-DISCRIMINATED — one test per variant)" do
    requirement_variants.each do |variant|
      it "dispatches #{variant[:type]} by value to #{variant[:klass]} (a KycRequirement)" do
        req = described_class.deserialize_kyc_requirement(requirement_wire(variant))

        expect(req).to be_a(variant[:klass])
        expect(req).to be_a(Dinie::KycRequirement)
        expect(req.requirement_type).to eq(variant[:type])
        expect(req.submitted).to be_a(Dinie::Internal::Model)
        expect(req.submitted.evidence_type).to eq(variant[:evidence])
      end

      it "models #{variant[:type]} subject presence (DS-SUBJECT: #{variant[:person] ? "person" : "company"})" do
        req = described_class.deserialize_kyc_requirement(requirement_wire(variant))

        if variant[:person]
          expect(req).to respond_to(:subject)
          expect(req.subject).to be_a(Dinie::KycSubject)
          expect(req.subject.subject_type).to eq("applicant")
        else
          expect(req).not_to respond_to(:subject) # company-wide requirements omit subject entirely
        end
      end
    end

    it "leaves submitted nil when no evidence has been uploaded yet (R-OPTIONAL on hydrate)" do
      req = described_class.deserialize_kyc_requirement(requirement_wire(requirement_variants[3], with_submitted: false))

      expect(req).to be_a(Dinie::CompanyDocumentRequirement)
      expect(req.submitted).to be_nil
    end

    it "raises a typed Dinie::Error on an unknown requirement_type (never silent)" do
      expect { described_class.deserialize_kyc_requirement({ requirement_type: "passport" }) }
        .to raise_error(Dinie::Error, /Unknown KycRequirement requirement_type: "passport"/)
    end
  end

  # V0.5: KycAttachment: submitted_at: Integer|nil → submitted: Boolean.
  # Submitted classes are concrete (IdentityCnhSubmitted, etc.) — all extend Internal::Model.
  describe ".deserialize_identity_submitted (DS-IMPLICIT — const evidence_type fallback)" do
    it "hydrates CNH physical evidence — front + back attachments (DS-COLLAPSE)" do
      wire = {
        evidence_type: "cnh",
        attachments: [
          { attachment_type: "front", submitted: true },
          { attachment_type: "back", submitted: false }
        ],
        review_status: "pending", review_reason: nil
      }

      submitted = described_class.deserialize_identity_submitted(wire)

      expect(submitted).to be_a(Dinie::Internal::Model)
      expect(submitted.evidence_type).to eq("cnh")
      expect(submitted.attachments.map(&:class)).to eq([Dinie::IdentityCnhAttachment, Dinie::IdentityCnhAttachment])
      expect(submitted.attachments.map(&:attachment_type)).to eq(%w[front back])
      expect(submitted.attachments[1].submitted).to be(false) # not-yet-submitted slot
    end

    it "hydrates CNH digital evidence — a single file attachment (DS-COLLAPSE)" do
      wire = {
        evidence_type: "cnh",
        attachments: [{ attachment_type: "file", submitted: true }],
        review_status: "accepted", review_reason: nil
      }

      submitted = described_class.deserialize_identity_submitted(wire)

      expect(submitted.attachments.size).to eq(1)
      expect(submitted.attachments.first.attachment_type).to eq("file")
    end

    it "hydrates RG evidence" do
      submitted = described_class.deserialize_identity_submitted(submitted_wire(evidence_type: "rg",
                                                                                attachment_type: "front"))

      expect(submitted.evidence_type).to eq("rg")
    end

    it "raises a typed Dinie::Error on an unknown identity evidence_type" do
      expect { described_class.deserialize_identity_submitted({ evidence_type: "passport" }) }
        .to raise_error(Dinie::Error, /Unknown IdentitySubmitted evidence_type: "passport"/)
    end
  end

  # ── The ten upload union members (discriminator evidence_type → multipart field-map) ──
  upload_variants = [
    { evidence: "cnh", requirement_id: "identity_003XXXXXXXXXXXXXXX", attachment: "front", file: true },
    { evidence: "rg", requirement_id: "identity_003XXXXXXXXXXXXXXX", attachment: "back", file: true },
    { evidence: "selfie", requirement_id: "selfie_003XXXXXXXXXXXXXXX", attachment: "photo", file: true },
    { evidence: "proof_of_address", requirement_id: "proof_of_address_003XXXXXXXXXXXXXXX",
      attachment: "file", file: true },
    { evidence: "ccmei", requirement_id: "company_document", attachment: "file", file: true },
    { evidence: "ei_mei", requirement_id: "ei_mei_documents", attachment: "ccmei", file: true },
    { evidence: "income_statement", requirement_id: "income_statement", attachment: "file", file: true },
    { evidence: "articles_of_association", requirement_id: "articles_of_association", attachment: "file", file: true },
    { evidence: "eireli_incorporation_statement", requirement_id: "eireli_incorporation_statement",
      attachment: "file", file: true },
    { evidence: "email", requirement_id: "email_003XXXXXXXXXXXXXXX", attachment: "email", file: false }
  ].freeze

  # V0.5: function renamed to serialize_kyc_upload.
  describe ".serialize_kyc_upload (DS-DISCRIMINATED-REQUEST + DS-MULTIPART — one test per variant)" do
    upload_variants.each do |variant|
      it "serializes the #{variant[:evidence]} upload to its multipart field-map" do
        base = { evidence_type: variant[:evidence], requirement_id: variant[:requirement_id],
                 attachment_type: variant[:attachment] }

        if variant[:file]
          form = described_class.serialize_kyc_upload(**base, file: "BINARY-BYTES")

          expect(form.fields).to eq(attachment_type: variant[:attachment], evidence_type: variant[:evidence],
                                    requirement_id: variant[:requirement_id])
          expect(form.file).to eq("BINARY-BYTES")
        else
          form = described_class.serialize_kyc_upload(**base, value: "co-owner@example.com")

          expect(form.fields).to eq(attachment_type: variant[:attachment], evidence_type: variant[:evidence],
                                    requirement_id: variant[:requirement_id], value: "co-owner@example.com")
          expect(form.file).to be_nil
        end
      end
    end

    it "orders the scalar fields alphabetically (R-ORDER)" do
      form = described_class.serialize_kyc_upload(evidence_type: "selfie", requirement_id: "selfie_003XXXXXXXXXXXXXXX",
                                                  attachment_type: "photo", file: "x")

      expect(form.fields.keys).to eq(%i[attachment_type evidence_type requirement_id])
    end

    it "raises a typed Dinie::Error on an unknown upload evidence_type" do
      expect do
        described_class.serialize_kyc_upload(evidence_type: "passport", requirement_id: "x", attachment_type: "front",
                                             file: "x")
      end.to raise_error(Dinie::Error, /Unknown KycUpload evidence_type: "passport"/)
    end

    it "raises when a file variant is missing its file:" do
      expect do
        described_class.serialize_kyc_upload(evidence_type: "cnh", requirement_id: "identity_003XXXXXXXXXXXXXXX",
                                             attachment_type: "front")
      end.to raise_error(Dinie::Error, /evidence_type="cnh" requires a `file:`/)
    end

    it "raises when the email variant is missing its value:" do
      expect do
        described_class.serialize_kyc_upload(evidence_type: "email", requirement_id: "email_003XXXXXXXXXXXXXXX",
                                             attachment_type: "email")
      end.to raise_error(Dinie::Error, /evidence_type="email" requires a `value:`/)
    end
  end

  describe "pattern matching (the partner discriminates by class — RB9)" do
    it "matches a variant by class with case/when" do
      req = described_class.deserialize_kyc_requirement(requirement_wire(requirement_variants[0]))

      label = case req
              when Dinie::IdentityRequirement then :identity
              when Dinie::SelfieRequirement then :selfie
              end

      expect(label).to eq(:identity)
    end

    it "supports deconstruct_keys for pattern matching on attributes" do
      req = described_class.deserialize_kyc_requirement(requirement_wire(requirement_variants[8])) # email

      matched =
        case req
        in { requirement_type: "email", subject: Dinie::KycSubject => subject }
          subject.subject_type
        end

      expect(matched).to eq("applicant")
    end
  end

  # V0.5: KycAttachment uses submitted: Boolean; method renamed to deserialize_kyc_requirement.
  describe "exact round-trip (the conformance-shape guarantee — story 012)" do
    it "round-trips an identity requirement with nested CNH submitted" do
      wire = {
        requirement_type: "identity", requirement_id: "identity_003XXXXXXXXXXXXXXX",
        label: "Documento de identidade", mandatory: true,
        subject: { id: "003XXXXXXXXXXXXXXX", name: "Joao Silva", subject_type: "applicant" },
        submitted: {
          evidence_type: "cnh",
          attachments: [
            { attachment_type: "front", submitted: true },
            { attachment_type: "back", submitted: false }
          ],
          review_status: "pending", review_reason: nil
        }
      }

      expect(deep_h(described_class.deserialize_kyc_requirement(wire))).to eq(wire)
    end

    it "round-trips a company-wide requirement (no subject)" do
      wire = {
        requirement_type: "income_statement", requirement_id: "income_statement",
        label: "Declaração de faturamento", mandatory: true,
        submitted: {
          evidence_type: "income_statement",
          attachments: [{ attachment_type: "file", submitted: true }],
          review_status: "accepted", review_reason: nil
        }
      }

      expect(deep_h(described_class.deserialize_kyc_requirement(wire))).to eq(wire)
    end
  end

  # V0.5: KycAttachmentResponse shape changed from {id, uploaded_at, requirement} to {attachment_type, submitted}.
  describe "Dinie::KycAttachmentResponse" do
    let(:wire) { { attachment_type: "front", submitted: true } }

    it "hydrates and round-trips" do
      response = Dinie::KycAttachmentResponse.deserialize(wire)

      expect(response.attachment_type).to eq("front")
      expect(response.submitted).to be(true)
      expect(response.to_h).to eq(wire)
    end
  end

  describe "enum value catalogs" do
    it "lists ReviewStatus values in contract order" do
      expect(Dinie::ReviewStatus::ALL).to eq(%w[pending accepted rejected])
    end

    it "lists KycSubjectType values in contract order" do
      expect(Dinie::KycSubjectType::ALL).to eq(%w[applicant co_owner])
    end
  end
end

# Resource tier — the multipart `create` and the `start_kyc_review` trigger over a real client.
RSpec.describe Dinie::Resources::Customers::KycAttachments do
  let(:base_url) { "https://api.dinie.test/api/v3" }
  let(:token_url) { "#{base_url}/auth/token" }
  let(:customer_id) { "cust_550e8400e29b41d4a716446655440000" }
  let(:client) { Dinie::Client.new(client_id: "id-1", client_secret: "secret-1", base_url:) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("DINIE_BASE_URL", nil).and_return(nil)
    stub_request(:post, token_url)
      .to_return(status: 200, body: JSON.generate(access_token: "tok-1", token_type: "bearer", expires_in: 3_600))
  end

  # V0.5: KycAttachmentResponse shape is now {attachment_type, submitted}.
  let(:attachment_response_wire) do
    { attachment_type: "front", submitted: true }
  end

  describe "#create (multipart upload → 201)" do
    let(:url) { "#{base_url}/customers/#{customer_id}/kyc-attachments" }

    before { stub_request(:post, url).to_return(status: 201, body: JSON.generate(attachment_response_wire)) }

    it "POSTs multipart/form-data with the scalar fields + the binary file, and hydrates the response" do
      response = client.customers.kyc_attachments.create(
        customer_id, evidence_type: "cnh", requirement_id: "identity_003XXXXXXXXXXXXXXX",
                     attachment_type: "front", file: StringIO.new("CNH-FRONT-BYTES")
      )

      multipart_post = a_request(:post, url).with do |req|
        req.headers["Content-Type"].to_s.start_with?("multipart/form-data") &&
          req.body.include?("evidence_type") && req.body.include?("identity_003XXXXXXXXXXXXXXX") &&
          req.body.include?("CNH-FRONT-BYTES")
      end
      expect(multipart_post).to have_been_made
      # V0.5: KycAttachmentResponse is {attachment_type, submitted}
      expect(response).to be_a(Dinie::KycAttachmentResponse)
      expect(response.attachment_type).to eq("front")
      expect(response.submitted).to be(true)
    end

    it "sends the email variant as multipart with a `value` field (no file part)" do
      stub_request(:post, url).to_return(status: 201, body: JSON.generate(attachment_response_wire))

      client.customers.kyc_attachments.create(
        customer_id, evidence_type: "email", requirement_id: "email_003XXXXXXXXXXXXXXX",
                     attachment_type: "email", value: "co-owner@example.com"
      )

      multipart_post = a_request(:post, url).with do |req|
        req.headers["Content-Type"].to_s.start_with?("multipart/form-data") &&
          req.body.include?("co-owner@example.com")
      end
      expect(multipart_post).to have_been_made
    end

    it "auto-carries an idempotency key (POST)" do
      client.customers.kyc_attachments.create(
        customer_id, evidence_type: "cnh", requirement_id: "identity_003XXXXXXXXXXXXXXX",
                     attachment_type: "front", file: StringIO.new("x")
      )

      idempotent = a_request(:post, url).with { |req| !req.headers["X-Idempotency-Key"].to_s.empty? }
      expect(idempotent).to have_been_made
    end

    it "raises a typed NotFoundError on a 404" do
      stub_request(:post, url).to_return(
        status: 404, headers: { "Content-Type" => "application/problem+json" },
        body: JSON.generate(type: "https://docs.dinie.com/errors/not-found", title: "Not Found",
                            status: 404, detail: "Customer ID does not exist", code: "customer_not_found")
      )

      expect do
        client.customers.kyc_attachments.create(
          customer_id, evidence_type: "cnh", requirement_id: "identity_003XXXXXXXXXXXXXXX",
                       attachment_type: "front", file: StringIO.new("x")
        )
      end.to raise_error(Dinie::NotFoundError)
    end
  end

  describe "#start_kyc_review (202 → nil)" do
    let(:url) { "#{base_url}/customers/#{customer_id}/kyc-review" }

    it "POSTs body-less, returns nil, and auto-carries an idempotency key" do
      stub_request(:post, url).to_return(status: 202, body: "")

      result = client.customers.start_kyc_review(customer_id)

      expect(result).to be_nil
      bodyless = a_request(:post, url).with { |req| req.body.nil? || req.body.empty? }
      expect(bodyless).to have_been_made
      idempotent = a_request(:post, url).with { |req| !req.headers["X-Idempotency-Key"].to_s.empty? }
      expect(idempotent).to have_been_made
    end
  end
end

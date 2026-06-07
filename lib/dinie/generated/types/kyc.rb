# frozen_string_literal: true

require_relative "../../runtime/model"

module Dinie
  module ReviewStatus
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    ALL = [PENDING, ACCEPTED, REJECTED].freeze
  end

  module KycSubjectType
    APPLICANT = "applicant"
    CO_OWNER = "co_owner"
    ALL = [APPLICANT, CO_OWNER].freeze
  end

  class KycSubject < Internal::Model
    attribute :id, :name, :subject_type

    def self.deserialize(raw)
      new(
        id: raw[:id],
        name: raw[:name],
        subject_type: raw[:subject_type]
      )
    end
  end

  class ArticlesOfAssociationAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class CompanyDocumentAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class EiMeiDocumentsAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class EireliIncorporationStatementAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class EmailAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class IdentityCnhAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class IdentityRgAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class IncomeStatementAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class ProofOfAddressAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  class SelfieAttachment < Internal::Model
    attribute :attachment_type, :submitted

    def self.deserialize(raw)
      new(
        attachment_type: raw[:attachment_type],
        submitted: raw[:submitted]
      )
    end
  end

  def self.kyc_dispatch_error(union, discriminator, value)
    Dinie::Error.new(
      "Unknown #{union} #{discriminator}: #{value.inspect}. This discriminator value is not " \
      "declared in the openapi oneOf mapping — the SDK and contract are out of sync."
    )
  end

  class ArticlesOfAssociationSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| ArticlesOfAssociationAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class CompanyDocumentSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| CompanyDocumentAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class EiMeiDocumentsSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| EiMeiDocumentsAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class EireliIncorporationStatementSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| EireliIncorporationStatementAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class EmailSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| EmailAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class IdentityCnhSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| IdentityCnhAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class IdentityRgSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| IdentityRgAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class IncomeStatementSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| IncomeStatementAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class ProofOfAddressSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| ProofOfAddressAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  class SelfieSubmitted < Internal::Model
    attribute :attachments, :evidence_type, :review_reason, :review_status

    def self.deserialize(raw)
      new(
        attachments: raw[:attachments].map { |item| SelfieAttachment.deserialize(item) },
        evidence_type: raw[:evidence_type],
        review_reason: raw[:review_reason],
        review_status: raw[:review_status]
      )
    end
  end

  def self.deserialize_identity_submitted(raw)
    case raw[:evidence_type]
    when "cnh" then IdentityCnhSubmitted.deserialize(raw)
    when "rg" then IdentityRgSubmitted.deserialize(raw)
    else raise kyc_dispatch_error("IdentitySubmitted", "evidence_type", raw[:evidence_type])
    end
  end

  class KycRequirement < Internal::Model
  end

  class IdentityRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        subject: KycSubject.deserialize(raw[:subject]),
        submitted: raw[:submitted] && Dinie.deserialize_identity_submitted(raw[:submitted])
      )
    end
  end

  class SelfieRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        subject: KycSubject.deserialize(raw[:subject]),
        submitted: raw[:submitted] && SelfieSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class ProofOfAddressRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        subject: KycSubject.deserialize(raw[:subject]),
        submitted: raw[:submitted] && ProofOfAddressSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class CompanyDocumentRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        submitted: raw[:submitted] && CompanyDocumentSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class EiMeiDocumentsRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        submitted: raw[:submitted] && EiMeiDocumentsSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class IncomeStatementRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        submitted: raw[:submitted] && IncomeStatementSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class ArticlesOfAssociationRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        submitted: raw[:submitted] && ArticlesOfAssociationSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class EireliIncorporationStatementRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        submitted: raw[:submitted] && EireliIncorporationStatementSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  class EmailRequirement < KycRequirement
    attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

    def self.deserialize(raw)
      new(
        label: raw[:label],
        mandatory: raw[:mandatory],
        requirement_id: raw[:requirement_id],
        requirement_type: raw[:requirement_type],
        subject: KycSubject.deserialize(raw[:subject]),
        submitted: raw[:submitted] && EmailSubmitted.deserialize(raw[:submitted])
      )
    end
  end

  def self.deserialize_kyc_requirement(raw)
    case raw[:requirement_type]
    when "identity" then IdentityRequirement.deserialize(raw)
    when "selfie" then SelfieRequirement.deserialize(raw)
    when "proof_of_address" then ProofOfAddressRequirement.deserialize(raw)
    when "company_document" then CompanyDocumentRequirement.deserialize(raw)
    when "ei_mei_documents" then EiMeiDocumentsRequirement.deserialize(raw)
    when "income_statement" then IncomeStatementRequirement.deserialize(raw)
    when "articles_of_association" then ArticlesOfAssociationRequirement.deserialize(raw)
    when "eireli_incorporation_statement" then EireliIncorporationStatementRequirement.deserialize(raw)
    when "email" then EmailRequirement.deserialize(raw)
    else raise kyc_dispatch_error("KycRequirement", "requirement_type", raw[:requirement_type])
    end
  end

  KycUploadForm = Struct.new(:fields, :file, keyword_init: true)

  KYC_FILE_UPLOAD_EVIDENCE_TYPES = %w[
    cnh rg selfie proof_of_address ccmei ei_mei income_statement articles_of_association eireli_incorporation_statement
  ].freeze

  def self.serialize_kyc_upload(evidence_type:, requirement_id:, attachment_type:, file: Internal::OMIT,
                                value: Internal::OMIT)
    fields = { attachment_type:, evidence_type:, requirement_id: }
    case evidence_type
    when *KYC_FILE_UPLOAD_EVIDENCE_TYPES
      if Internal.omitted?(file)
        raise Dinie::Error, "KYC upload evidence_type=#{evidence_type.inspect} requires a `file:`"
      end

      KycUploadForm.new(fields:, file:)
    when "email"
      raise Dinie::Error, "KYC upload evidence_type=\"email\" requires a `value:`" if Internal.omitted?(value)

      KycUploadForm.new(fields: fields.merge(value:), file: nil)
    else
      raise kyc_dispatch_error("KycUpload", "evidence_type", evidence_type)
    end
  end
end

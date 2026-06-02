# frozen_string_literal: true

require_relative "../../../runtime/model"
require_relative "common"
require_relative "submitted"

# KYC *requirement* types + the `KycRequirement` discriminated union (architecture §6.3,
# §3.4-equiv — the hardest determinism shape in the project and the `comparison.md` canary).
# Hand-authored in V0.3; ports `sdk-js` `src/generated/types/kyc/requirements.ts` (@ `19c9bca`).
# A requirement is something the customer must verify (identity, address, company docs…). The
# openapi models the family as an `oneOf` of nine `*Requirement` schemas with an EXPLICIT
# `discriminator: {propertyName: requirement_type, mapping}`.
#
# ── DS-DISCRIMINATED (the headline rule — base + subclasses, value-driven dispatch) ──
# openapi `oneOf` + explicit `discriminator` →
#   1. a shared base {Kyc::Requirement} (the common ancestor — partners discriminate by CLASS:
#      `case requirement; when Dinie::Kyc::IdentityRequirement`);
#   2. one subclass per member, each carrying its `requirement_type` const as data and listing its
#      own attributes alphabetically (R-ORDER);
#   3. {Kyc.deserialize_requirement} is a `case raw[:requirement_type]` whose `when` values are
#      EXACTLY the openapi `mapping` keys, each delegating to the member's `deserialize`;
#   4. an unmapped value raises {Kyc.dispatch_error} (never a silent `nil`).
# The `case` is table-driven by the mapping — NO bespoke per-variant control flow. This is the
# `case/when` (Ruby) that mirrors the TS `switch`: COMMON in principle (table-driven), SPECIFIC in
# construct (`case/when` vs `switch`) — the `comparison.md` §2.4 verdict.
#
# ── DS-CONST-ID (const vs pattern `requirement_id`) ──
# Person-specific requirements (identity/selfie/proof-of-address/email) carry a pattern
# `requirement_id` (`identity_{subject_id}`, …); company-wide ones carry a `const requirement_id`
# (= the requirement type). Both surface as a plain `String` in Ruby (the const/pattern is a wire
# constraint, documented, not encoded in the type).
#
# ── DS-SUBJECT (presence-driven optionality) ──
# Person-specific requirements REQUIRE `subject` (a {Kyc::Subject}); company-wide ones OMIT it
# entirely (it is not in their schema, not merely optional). Each subclass declares `subject` only
# when its schema does — so the base declares no attributes and every concrete variant lists its
# full set, keeping R-ORDER exact per class.
#
# ── R-OPTIONAL on `submitted` ──
# `submitted` is optional (absent until something is uploaded). On hydrate an absent optional
# arrives as `nil` (Ruby collapses absent/null on reads), so `deserialize` carries
# `raw[:submitted] && …` — the attribute is always declared (the base requires every declared key),
# its value `nil` when no evidence exists yet.
#
# ── runtime ↔ generated boundary (architecture §4) ──
# Lives in `generated/`. Imports the runtime model base and the sibling KYC leaves only. Public
# surface lives under `Dinie::Kyc::*Requirement`; the `deserialize*` are the internal hydrate path
# consumed by `./attachment.rb`, the customers resource, `../customer.rb`, and conformance (012).
module Dinie
  module Kyc
    # Abstract base for the nine requirement variants — the common ancestor partners pattern-match
    # on (`case requirement; when Dinie::Kyc::Requirement`). Declares no attributes; each concrete
    # variant lists its own (R-ORDER). Never instantiated directly.
    class Requirement < Internal::Model
    end

    # Identity-document requirement (CNH or RG). Person-specific (carries a {Kyc::Subject}); its
    # `submitted` is the CNH|RG evidence (DS-IMPLICIT, hydrated via {deserialize_identity_submitted}).
    class IdentityRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [IdentityRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          subject: Subject.deserialize(raw[:subject]),
          submitted: raw[:submitted] && Kyc.deserialize_identity_submitted(raw[:submitted])
        )
      end
    end

    # Selfie requirement. Person-specific.
    class SelfieRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [SelfieRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          subject: Subject.deserialize(raw[:subject]),
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Proof-of-address requirement. Person-specific.
    class ProofOfAddressRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [ProofOfAddressRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          subject: Subject.deserialize(raw[:subject]),
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Company-document (CCMEI) requirement. Company-wide — no subject (DS-SUBJECT); `requirement_id`
    # is the const `company_document` (DS-CONST-ID).
    class CompanyDocumentRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [CompanyDocumentRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # EI/MEI documents requirement (EI registration + CCMEI). Company-wide.
    class EiMeiDocumentsRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [EiMeiDocumentsRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Income-statement (DRE) requirement. Company-wide.
    class IncomeStatementRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [IncomeStatementRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Articles-of-association (contrato social) requirement. Company-wide.
    class ArticlesOfAssociationRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [ArticlesOfAssociationRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # EIRELI incorporation-statement requirement. Company-wide.
    class EireliIncorporationStatementRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [EireliIncorporationStatementRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Co-owner email-collection requirement (for CCB digital signature). Person-specific.
    class EmailRequirement < Requirement
      attribute :label, :mandatory, :requirement_id, :requirement_type, :subject, :submitted

      # @param raw [Hash{Symbol => Object}] the wire object
      # @return [EmailRequirement]
      def self.deserialize(raw)
        new(
          label: raw[:label],
          mandatory: raw[:mandatory],
          requirement_id: raw[:requirement_id],
          requirement_type: raw[:requirement_type],
          subject: Subject.deserialize(raw[:subject]),
          submitted: raw[:submitted] && Kyc.deserialize_submitted(raw[:submitted])
        )
      end
    end

    # Hydrate any wire {Requirement} by dispatching on the explicit `requirement_type` discriminator
    # (DS-DISCRIMINATED). The `when` values are EXACTLY the openapi `discriminator.mapping` keys;
    # an unmapped value raises {dispatch_error}. Table-driven — the V0.5 generator reproduces this
    # from the schema, and it is the Ruby `case/when` the `comparison.md` canary compares to the TS
    # `switch`.
    #
    # @param raw [Hash{Symbol => Object}] the wire object (must carry `requirement_type`)
    # @return [Requirement] the concrete variant
    # @raise [Dinie::Error] when `requirement_type` is not in the openapi mapping
    def self.deserialize_requirement(raw)
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
      else raise dispatch_error("KycRequirement", "requirement_type", raw[:requirement_type])
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe Dinie::Internal::Model do
  # A representative subclass declared in alphabetical (R-ORDER) order, mixing PII and
  # non-PII fields so redaction can be exercised.
  model_class = Class.new(described_class) do
    attribute :cpf, :id, :name, :status
  end

  let(:attrs) { { cpf: "12345678900", id: "cust_1", name: "Ana", status: "active" } }

  subject(:model) { model_class.new(**attrs) }

  describe ".attribute / R-ORDER" do
    it "registers attributes in declaration order" do
      expect(model_class.attributes).to eq(%i[cpf id name status])
    end

    it "generates a reader per attribute" do
      expect([model.cpf, model.id, model.name, model.status])
        .to eq(%w[12345678900 cust_1 Ana active])
    end

    it "is idempotent when an attribute is declared twice" do
      klass = Class.new(described_class) do
        attribute :id
        attribute :id, :name
      end
      expect(klass.attributes).to eq(%i[id name])
    end

    it "inherits the parent attribute list in subclasses" do
      child = Class.new(model_class) { attribute :extra }
      expect(child.attributes).to eq(%i[cpf id name status extra])
      expect(model_class.attributes).to eq(%i[cpf id name status]) # parent untouched
    end
  end

  describe "#to_h" do
    it "returns attributes in declaration order (deterministic)" do
      expect(model.to_h).to eq(attrs)
      expect(model.to_h.keys).to eq(%i[cpf id name status])
    end

    it "aliases to_hash" do
      expect(model.to_hash).to eq(model.to_h)
    end
  end

  describe "#deconstruct_keys / pattern matching" do
    it "matches by keys via case/in" do
      result =
        case model
        in { status: "active", id: }
          id
        else
          :no_match
        end
      expect(result).to eq("cust_1")
    end

    it "exposes the full attribute hash" do
      expect(model.deconstruct_keys(nil)).to eq(attrs)
      expect(model.deconstruct_keys(%i[status])).to eq(attrs)
    end
  end

  describe "#== / value-equality" do
    it "is equal to another instance with the same attributes" do
      expect(model).to eq(model_class.new(**attrs))
    end

    it "differs when any attribute differs" do
      expect(model).not_to eq(model_class.new(**attrs, name: "Bea"))
    end

    it "differs from an instance of another class with the same attributes" do
      other_class = Class.new(described_class) { attribute :cpf, :id, :name, :status }
      expect(model).not_to eq(other_class.new(**attrs))
    end

    it "is usable as a Hash key (eql? + hash are consistent)" do
      store = { model => :ok }
      expect(store[model_class.new(**attrs)]).to eq(:ok)
      expect(model.hash).to eq(model_class.new(**attrs).hash)
    end
  end

  describe "#initialize" do
    it "freezes the instance" do
      expect(model).to be_frozen
    end

    it "raises on a missing required attribute" do
      expect { model_class.new(cpf: "x", id: "y", name: "z") }
        .to raise_error(ArgumentError, /missing keyword: :status/)
    end

    it "raises listing all missing attributes" do
      expect { model_class.new(cpf: "x") }
        .to raise_error(ArgumentError, /missing keywords: :id, :name, :status/)
    end

    it "raises on an unknown attribute" do
      expect { model_class.new(**attrs, bogus: 1) }
        .to raise_error(ArgumentError, /unknown keyword: :bogus/)
    end
  end

  describe "#inspect" do
    it "redacts PII attributes" do
      expect(model.inspect).to include("cpf=[REDACTED]")
    end

    it "shows non-PII attributes verbatim" do
      expect(model.inspect).to include('id="cust_1"', 'name="Ana"', 'status="active"')
    end

    it "does not leak the PII value" do
      expect(model.inspect).not_to include("12345678900")
    end
  end
end

RSpec.describe Dinie::Internal::OMIT do
  it "is a single, frozen sentinel object" do
    expect(described_class).to be_frozen
    expect(described_class).to equal(Dinie::Internal::OMIT)
  end

  it "has a descriptive inspect" do
    expect(described_class.inspect).to eq("#<Dinie::Internal::OMIT>")
  end

  describe "Dinie::Internal.omitted?" do
    it "is true only for the sentinel (by identity)" do
      expect(Dinie::Internal.omitted?(described_class)).to be(true)
    end

    it "is false for nil and other values" do
      expect(Dinie::Internal.omitted?(nil)).to be(false)
      expect(Dinie::Internal.omitted?("")).to be(false)
      expect(Dinie::Internal.omitted?(Object.new)).to be(false)
    end
  end
end

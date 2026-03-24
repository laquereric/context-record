# frozen_string_literal: true

RSpec.describe ContextRecord::ContextPrimitive do
  describe "#initialize" do
    it "accepts type and value" do
      p = described_class.new(type: "vv:Action", value: "read")
      expect(p.type).to eq("vv:Action")
      expect(p.value).to eq("read")
    end

    it "accepts id alone (named node)" do
      p = described_class.new(id: "https://example.com/entity/1")
      expect(p.id).to eq("https://example.com/entity/1")
      expect(p.type).to be_nil
    end

    it "accepts language with string value" do
      p = described_class.new(value: "hello", language: "en")
      expect(p.language).to eq("en")
    end

    it "raises if neither type nor id given" do
      expect { described_class.new(value: "x") }.to raise_error(ArgumentError, /type.*id/)
    end

    it "raises if language given with non-string value" do
      expect { described_class.new(type: "vv:Literal", value: 42, language: "en") }
        .to raise_error(ArgumentError, /language.*string/)
    end

    it "raises if both language and type are given" do
      expect { described_class.new(type: "vv:Literal", value: "hi", language: "en") }
        .to raise_error(ArgumentError, /mutually exclusive/)
    end

    it "is frozen after initialization" do
      p = described_class.new(type: "vv:Action", value: "read")
      expect(p).to be_frozen
    end

    it "deep-freezes hash values" do
      p = described_class.new(type: "vv:Entity", value: { name: "Alice" })
      expect(p.value).to be_frozen
      expect(p.value[:name]).to be_frozen
    end

    it "accepts vv:EvalResult type" do
      expect { described_class.new(type: "vv:EvalResult", value: "pass") }.not_to raise_error
    end
  end

  describe "#to_json_ld" do
    it "returns a Hash with sorted keys" do
      p = described_class.new(type: "vv:Action", value: "read")
      result = p.to_json_ld
      expect(result.keys).to eq(result.keys.sort)
    end

    it "includes @type and @value for a typed literal" do
      p = described_class.new(type: "vv:Action", value: "read")
      expect(p.to_json_ld).to eq({ "@type" => "vv:Action", "@value" => "read" })
    end

    it "includes only @id for a named node" do
      p = described_class.new(id: "https://example.com/1")
      expect(p.to_json_ld).to eq({ "@id" => "https://example.com/1" })
    end

    it "includes @language and @value for a language-tagged string" do
      p = described_class.new(value: "bonjour", language: "fr")
      expect(p.to_json_ld).to eq({ "@language" => "fr", "@value" => "bonjour" })
    end

    it "sorts nested hash keys deterministically" do
      p = described_class.new(type: "vv:Entity", value: { z: 1, a: 2 })
      inner = p.to_json_ld["@value"]
      expect(inner.keys).to eq(inner.keys.sort)
    end

    it "is deterministic: same inputs produce identical output" do
      p1 = described_class.new(type: "vv:Entity", value: { name: "Alice", age: 30 })
      p2 = described_class.new(type: "vv:Entity", value: { name: "Alice", age: 30 })
      expect(p1.to_json_ld).to eq(p2.to_json_ld)
    end
  end

  describe "#to_json" do
    it "returns a JSON string" do
      p = described_class.new(type: "vv:Action", value: "read")
      parsed = JSON.parse(p.to_json)
      expect(parsed["@type"]).to eq("vv:Action")
      expect(parsed["@value"]).to eq("read")
    end

    it "is deterministic: same inputs produce identical JSON bytes" do
      p1 = described_class.new(type: "vv:Literal", value: "hello")
      p2 = described_class.new(type: "vv:Literal", value: "hello")
      expect(p1.to_json).to eq(p2.to_json)
    end
  end

  describe "#==" do
    it "is equal when to_json_ld matches" do
      p1 = described_class.new(type: "vv:Action", value: "read")
      p2 = described_class.new(type: "vv:Action", value: "read")
      expect(p1).to eq(p2)
    end

    it "is not equal when values differ" do
      p1 = described_class.new(type: "vv:Action", value: "read")
      p2 = described_class.new(type: "vv:Action", value: "write")
      expect(p1).not_to eq(p2)
    end
  end
end

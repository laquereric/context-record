# frozen_string_literal: true

require "spec_helper"

RSpec.describe ContextRecord::Ontology do
  describe ".valid_type?" do
    it "accepts the 7 original primitive types" do
      %w[vv:Action vv:Entity vv:Literal vv:Identifier vv:Relation vv:Event vv:EvalResult].each do |type|
        expect(described_class.valid_type?(type)).to be true
      end
    end

    it "accepts DomainEntity" do
      expect(described_class.valid_type?("vv:DomainEntity")).to be true
    end

    it "accepts Taxonomy" do
      expect(described_class.valid_type?("vv:Taxonomy")).to be true
    end

    it "rejects unknown types" do
      expect(described_class.valid_type?("vv:Bogus")).to be false
      expect(described_class.valid_type?("Action")).to be false
      expect(described_class.valid_type?("")).to be false
    end
  end

  describe ".primitive_type?" do
    it "accepts the 7 primitive types" do
      %w[vv:Action vv:Entity vv:Literal vv:Identifier vv:Relation vv:Event vv:EvalResult].each do |type|
        expect(described_class.primitive_type?(type)).to be true
      end
    end

    it "rejects DomainEntity (not a primitive)" do
      expect(described_class.primitive_type?("vv:DomainEntity")).to be false
    end
  end

  describe ".relationship_types" do
    it "returns all declared relationship properties" do
      rels = described_class.relationship_types
      expect(rels).to include("vv:isCompatibleWith")
      expect(rels).to include("vv:isNotCompatibleWith")
      expect(rels).to include("vv:isAccessoryFor")
      expect(rels).to include("vv:competesWith")
      expect(rels).to include("vv:supersedes")
      expect(rels).to include("vv:manufacturedBy")
      expect(rels).to include("vv:hasFeature")
    end

    it "returns 7 relationship types" do
      expect(described_class.relationship_types.size).to eq(7)
    end
  end

  describe ".all_properties" do
    it "includes relationships, links, and eval properties" do
      props = described_class.all_properties
      expect(props).to include("vv:isCompatibleWith")
      expect(props).to include("vv:relatedTo")
      expect(props).to include("vv:causedBy")
      expect(props).to include("vv:testedProperty")
      expect(props).to include("vv:groundTruth")
    end
  end

  describe ".symmetric?" do
    it "returns true for symmetric properties" do
      expect(described_class.symmetric?("vv:isCompatibleWith")).to be true
      expect(described_class.symmetric?("vv:isNotCompatibleWith")).to be true
      expect(described_class.symmetric?("vv:competesWith")).to be true
      expect(described_class.symmetric?("vv:relatedTo")).to be true
    end

    it "returns false for non-symmetric properties" do
      expect(described_class.symmetric?("vv:supersedes")).to be false
      expect(described_class.symmetric?("vv:isAccessoryFor")).to be false
      expect(described_class.symmetric?("vv:manufacturedBy")).to be false
      expect(described_class.symmetric?("vv:hasFeature")).to be false
      expect(described_class.symmetric?("vv:causedBy")).to be false
    end

    it "returns false for unknown properties" do
      expect(described_class.symmetric?("vv:bogus")).to be false
    end
  end

  describe ".ontology_path" do
    it "points to a file that exists" do
      expect(File.exist?(described_class.ontology_path)).to be true
    end

    it "points to a .ttl file" do
      expect(described_class.ontology_path).to end_with("vv-ontology.ttl")
    end
  end

  describe ".context_path" do
    it "points to a file that exists" do
      expect(File.exist?(described_class.context_path)).to be true
    end

    it "points to valid JSON" do
      content = File.read(described_class.context_path)
      expect { JSON.parse(content) }.not_to raise_error
    end

    it "contains a @context key" do
      content = JSON.parse(File.read(described_class.context_path))
      expect(content).to have_key("@context")
    end

    it "maps vv: to the correct namespace" do
      content = JSON.parse(File.read(described_class.context_path))
      expect(content["@context"]["vv"]).to eq("https://verticalvertical.net/ns/biological#")
    end
  end

  describe "alignment with ContextPrimitive" do
    it "VALID_TYPES matches Ontology::PRIMITIVE_TYPES" do
      expect(ContextRecord::ContextPrimitive::VALID_TYPES).to eq(described_class::PRIMITIVE_TYPES)
    end
  end
end

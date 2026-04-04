# frozen_string_literal: true

require "spec_helper"
require "context_record/ttl_generator"

RSpec.describe ContextRecord::TtlGenerator do
  let(:generator) { described_class.new }

  describe "#generate" do
    it "produces valid TTL for a node" do
      ttl = generator.generate(
        source_id: "shure-sm7b",
        content: { "brand" => "Shure", "price" => 399 },
        node_type: "bandh:Product"
      )
      expect(ttl).to include("@prefix vv:")
      expect(ttl).to include("<urn:vv:shure-sm7b> a bandh:Product")
      expect(ttl).to include("vv:hasProperty")
    end

    it "uses property mappings when provided" do
      gen = described_class.new(property_mappings: { "brand" => "bandh:hasBrand" })
      ttl = gen.generate(
        source_id: "test",
        content: { "brand" => "Canon" },
        node_type: "bandh:Product"
      )
      expect(ttl).to include("bandh:hasBrand")
      expect(ttl).not_to include("vv:hasProperty")
    end

    it "handles empty properties" do
      ttl = generator.generate(source_id: "empty", content: {}, node_type: "vv:Entity")
      expect(ttl).to include("<urn:vv:empty> a vv:Entity .")
    end

    it "handles string properties as JSON" do
      ttl = generator.generate(
        source_id: "test",
        content: '{"name": "Test"}',
        node_type: "vv:Entity"
      )
      expect(ttl).to include("<urn:vv:test> a vv:Entity")
    end
  end

  describe "#generate_from_graph" do
    let(:nodes) do
      [
        { "id" => "node-a", "type" => "vv:Entity", "label" => "Node A", "properties" => { "color" => "red" } },
        { "id" => "node-b", "type" => "vv:Entity", "label" => "Node B", "properties" => {} }
      ]
    end

    let(:edges) do
      [
        { "source_id" => "node-a", "target_id" => "node-b", "rel_type" => "is_compatible_with", "properties" => '{"notes":"test edge"}' }
      ]
    end

    it "generates TTL for nodes and edges" do
      ttl = generator.generate_from_graph(nodes: nodes, edges: edges)
      expect(ttl).to include("<urn:vv:node-a> a vv:Entity")
      expect(ttl).to include("<urn:vv:node-b> a vv:Entity")
      expect(ttl).to include("vv:isCompatibleWith")
      expect(ttl).to include("# test edge")
    end

    it "includes prefix block" do
      ttl = generator.generate_from_graph(nodes: nodes, edges: [])
      expect(ttl).to include("@prefix vv:")
      expect(ttl).to include("@prefix rdf:")
      expect(ttl).to include("@prefix rdfs:")
    end

    it "maps relationship types to ontology names" do
      edges = [
        { "source_id" => "a", "target_id" => "b", "rel_type" => "competes_with", "properties" => nil }
      ]
      ttl = generator.generate_from_graph(nodes: [], edges: edges)
      expect(ttl).to include("vv:competesWith")
    end

    it "preserves already-namespaced rel_types" do
      edges = [
        { "source_id" => "a", "target_id" => "b", "rel_type" => "iadbot:isReadyFor", "properties" => nil }
      ]
      ttl = generator.generate_from_graph(nodes: [], edges: edges)
      expect(ttl).to include("iadbot:isReadyFor")
    end
  end

  describe "custom prefixes" do
    it "merges custom prefixes with defaults" do
      gen = described_class.new(prefixes: { "bandh" => "https://bandh.example.com/ns#" })
      ttl = gen.generate(source_id: "test", content: {}, node_type: "bandh:Product")
      expect(ttl).to include("@prefix bandh:")
      expect(ttl).to include("@prefix vv:")
    end
  end

  describe "literal encoding" do
    it "encodes strings" do
      ttl = generator.generate(source_id: "t", content: { "name" => "Shure SM7B" }, node_type: "vv:Entity")
      expect(ttl).to include('"Shure SM7B"')
    end

    it "encodes integers" do
      ttl = generator.generate(source_id: "t", content: { "price" => 399 }, node_type: "vv:Entity")
      expect(ttl).to include("399")
    end

    it "encodes booleans" do
      ttl = generator.generate(source_id: "t", content: { "active" => true }, node_type: "vv:Entity")
      expect(ttl).to include("xsd:boolean")
    end
  end
end

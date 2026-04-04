# frozen_string_literal: true

require "spec_helper"

RSpec.describe ContextRecord::ContextAssembler do
  let(:graph) { ContextRecord::GraphStore.new }

  before do
    graph.add_node(id: "p1", type: "vv:Product", label: "Widget A", properties: { price: 29.99, color: "red" })
    graph.add_node(id: "p2", type: "vv:Product", label: "Widget B", properties: { price: 49.99, color: "blue" })
    graph.add_node(id: "c1", type: "vv:Category", label: "Gadgets", properties: {})
    graph.add_node(id: "p3", type: "vv:Product", label: "Widget C", properties: { price: 19.99 })

    graph.add_edge(source_id: "p1", target_id: "p2", rel_type: "vv:isCompatibleWith", properties: { notes: "works together" })
    graph.add_edge(source_id: "p1", target_id: "c1", rel_type: "vv:belongsTo", properties: {})
    graph.add_edge(source_id: "p2", target_id: "p3", rel_type: "vv:isAccessoryFor", properties: {})
  end

  describe "#assemble" do
    context "with node_id only" do
      let(:assembler) { described_class.new(graph_store: graph) }

      it "returns a hash with :context and :sources" do
        result = assembler.assemble(node_id: "p1")
        expect(result).to have_key(:context)
        expect(result).to have_key(:sources)
      end

      it "includes structured data in context" do
        result = assembler.assemble(node_id: "p1")
        expect(result[:context]).to include("[STRUCTURED DATA]")
        expect(result[:context]).to include("Widget A")
      end

      it "does not include semantic section without vector_store" do
        result = assembler.assemble(node_id: "p1")
        expect(result[:context]).not_to include("[SEMANTIC DATA]")
      end

      it "does not include user query section when no query_text" do
        result = assembler.assemble(node_id: "p1")
        expect(result[:context]).not_to include("[USER QUERY]")
      end
    end

    context "with query_text and no vector_store" do
      let(:assembler) { described_class.new(graph_store: graph) }

      it "includes user query section but no semantic section" do
        result = assembler.assemble(node_id: "p1", query_text: "What goes with Widget A?")
        expect(result[:context]).to include("[USER QUERY]")
        expect(result[:context]).to include("What goes with Widget A?")
        expect(result[:context]).not_to include("[SEMANTIC DATA]")
      end
    end

    context "with vector_store" do
      let(:vector_store) { double("VectorStore") }
      let(:assembler) { described_class.new(graph_store: graph, vector_store: vector_store) }

      it "includes semantic section when query_text provided" do
        allow(vector_store).to receive(:search)
          .with("red widgets", top_k: 5)
          .and_return([{ text: "Widget A is a great red widget", score: 0.92 }])

        result = assembler.assemble(node_id: "p1", query_text: "red widgets")
        expect(result[:context]).to include("[SEMANTIC DATA]")
        expect(result[:context]).to include("great red widget")
        expect(result[:sources]).to include(a_hash_including(type: "vector", score: 0.92))
      end
    end

    context "with neither node_id nor query_text" do
      let(:assembler) { described_class.new(graph_store: graph) }

      it "returns empty context" do
        result = assembler.assemble
        expect(result[:context]).to eq("")
        expect(result[:sources]).to be_empty
      end
    end
  end

  describe "#structured_context" do
    let(:assembler) { described_class.new(graph_store: graph) }

    it "returns node and its neighbors" do
      entries = assembler.structured_context("p1")
      expect(entries.size).to eq(1)
      expect(entries.first[:node]["id"]).to eq("p1")
      expect(entries.first[:neighbors].size).to eq(2)
    end

    it "filters neighbors by rel_types" do
      entries = assembler.structured_context("p1", rel_types: ["vv:isCompatibleWith"])
      neighbor_ids = entries.first[:neighbors].map { |n| n[:node]["id"] }
      expect(neighbor_ids).to eq(["p2"])
    end

    it "returns empty array for missing node" do
      expect(assembler.structured_context("nonexistent")).to eq([])
    end
  end

  describe "#format_context" do
    let(:assembler) { described_class.new(graph_store: graph) }

    it "produces readable text with structured entries" do
      structured = [{
        node: { "id" => "p1", "type" => "vv:Product", "label" => "Widget A", "properties" => { "price" => 29.99 } },
        neighbors: [{ rel_type: "vv:isCompatibleWith", node: { "id" => "p2", "label" => "Widget B" } }]
      }]

      result = assembler.format_context(structured, [])
      expect(result[:context]).to include("vv:Product: Widget A")
      expect(result[:context]).to include("Properties: price: 29.99")
      expect(result[:context]).to include("vv:isCompatibleWith → Widget B")
    end

    it "builds sources with graph type and neighbor count" do
      structured = [{
        node: { "id" => "p1", "type" => "vv:Product", "label" => "Widget A", "properties" => {} },
        neighbors: [{ rel_type: "vv:isCompatibleWith", node: { "id" => "p2", "label" => "Widget B" } }]
      }]

      result = assembler.format_context(structured, [])
      expect(result[:sources]).to eq([{ type: "graph", node_id: "p1", neighbors: 1 }])
    end
  end
end

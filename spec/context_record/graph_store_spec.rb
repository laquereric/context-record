# frozen_string_literal: true

require "spec_helper"

RSpec.describe ContextRecord::GraphStore do
  let(:store) { described_class.new }

  before do
    store.add_node(id: "a", type: "vv:DomainEntity", label: "Node A", properties: { color: "red" })
    store.add_node(id: "b", type: "vv:DomainEntity", label: "Node B", properties: { color: "blue" })
    store.add_node(id: "c", type: "vv:DomainEntity", label: "Node C", properties: { color: "green" })
    store.add_node(id: "d", type: "vv:Entity", label: "Node D")

    store.add_edge(source_id: "a", target_id: "b", rel_type: "vv:isCompatibleWith", properties: { notes: "A works with B" })
    store.add_edge(source_id: "b", target_id: "c", rel_type: "vv:isCompatibleWith", properties: { notes: "B works with C" })
    store.add_edge(source_id: "a", target_id: "d", rel_type: "vv:isAccessoryFor", properties: { notes: "A is accessory for D" })
  end

  describe "#add_node / #find_node" do
    it "stores and retrieves a node" do
      node = store.find_node("a")
      expect(node["id"]).to eq("a")
      expect(node["type"]).to eq("vv:DomainEntity")
      expect(node["label"]).to eq("Node A")
      expect(node["properties"]).to eq({ "color" => "red" })
    end

    it "returns nil for missing node" do
      expect(store.find_node("missing")).to be_nil
    end
  end

  describe "#find_nodes" do
    it "returns all nodes" do
      expect(store.find_nodes.size).to eq(4)
    end

    it "filters by type" do
      expect(store.find_nodes(type: "vv:DomainEntity").size).to eq(3)
      expect(store.find_nodes(type: "vv:Entity").size).to eq(1)
    end
  end

  describe "#edges_by_type" do
    it "returns edges of the given type" do
      edges = store.edges_by_type("vv:isCompatibleWith")
      expect(edges.size).to eq(2)
    end

    it "returns empty for missing type" do
      expect(store.edges_by_type("vv:bogus")).to be_empty
    end
  end

  describe "#neighbors" do
    it "finds neighbors in both directions" do
      results = store.neighbors("b")
      ids = results.map { |r| r[:node]["id"] }
      expect(ids).to contain_exactly("a", "c")
    end

    it "filters by rel_type" do
      results = store.neighbors("a", rel_type: "vv:isAccessoryFor")
      expect(results.size).to eq(1)
      expect(results.first[:node]["id"]).to eq("d")
    end

    it "returns edge properties" do
      results = store.neighbors("a", rel_type: "vv:isCompatibleWith")
      expect(results.first[:edge_properties]).to include("notes" => "A works with B")
    end
  end

  describe "#two_hop" do
    it "finds nodes 2 hops away" do
      results = store.two_hop("a")
      ids = results.map { |r| r[:node]["id"] }
      expect(ids).to include("c")
    end

    it "includes the via node" do
      results = store.two_hop("a")
      via_labels = results.map { |r| r[:via] }
      expect(via_labels).to include("Node B")
    end

    it "does not include the start node" do
      results = store.two_hop("a")
      ids = results.map { |r| r[:node]["id"] }
      expect(ids).not_to include("a")
    end
  end

  describe "#subgraph" do
    it "returns nodes and edges within depth" do
      result = store.subgraph("a", max_depth: 1)
      node_ids = result[:nodes].map { |n| n["id"] }
      expect(node_ids).to contain_exactly("a", "b", "d")
    end

    it "respects max_depth" do
      result = store.subgraph("a", max_depth: 2)
      node_ids = result[:nodes].map { |n| n["id"] }
      expect(node_ids).to include("c")
    end

    it "includes typed edges" do
      result = store.subgraph("a", max_depth: 1)
      edge_types = result[:edges].map { |e| e[:rel_type] }
      expect(edge_types).to include("vv:isCompatibleWith", "vv:isAccessoryFor")
    end
  end

  describe "#node_count / #edge_count" do
    it "returns correct counts" do
      expect(store.node_count).to eq(4)
      expect(store.edge_count).to eq(3)
    end
  end

  describe "#stats" do
    it "returns node and edge type breakdowns" do
      s = store.stats
      expect(s[:nodes]).to eq(4)
      expect(s[:edges]).to eq(3)
      expect(s[:node_types]["vv:DomainEntity"]).to eq(3)
      expect(s[:edge_types]["vv:isCompatibleWith"]).to eq(2)
    end
  end

  describe "ontology validation" do
    let(:validated_store) do
      s = described_class.new
      s.load_ontology(
        node_types: %w[vv:DomainEntity vv:Entity],
        edge_types: %w[vv:isCompatibleWith]
      )
      s
    end

    it "accepts valid node types" do
      expect { validated_store.add_node(id: "x", type: "vv:DomainEntity") }.not_to raise_error
    end

    it "rejects invalid node types" do
      expect { validated_store.add_node(id: "x", type: "bogus:Type") }
        .to raise_error(ArgumentError, /not declared in ontology/)
    end

    it "accepts valid edge types" do
      validated_store.add_node(id: "x", type: "vv:DomainEntity")
      validated_store.add_node(id: "y", type: "vv:DomainEntity")
      expect { validated_store.add_edge(source_id: "x", target_id: "y", rel_type: "vv:isCompatibleWith") }
        .not_to raise_error
    end

    it "rejects invalid edge types" do
      validated_store.add_node(id: "x", type: "vv:DomainEntity")
      validated_store.add_node(id: "y", type: "vv:DomainEntity")
      expect { validated_store.add_edge(source_id: "x", target_id: "y", rel_type: "bogus:rel") }
        .to raise_error(ArgumentError, /not declared in ontology/)
    end

    it "skips validation when no ontology loaded" do
      plain = described_class.new
      expect { plain.add_node(id: "x", type: "anything:Goes") }.not_to raise_error
      expect { plain.add_edge(source_id: "x", target_id: "x", rel_type: "any:rel") }.not_to raise_error
    end
  end
end

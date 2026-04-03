# frozen_string_literal: true

require "sqlite3"
require "json"

module ContextRecord
  # Generic SQLite-backed Knowledge Graph for structured retrieval.
  #
  # Stores typed nodes and typed edges, enabling multi-hop traversal,
  # filtered queries, and compatibility reasoning across any domain.
  #
  # Domain-specific subclasses (Moe4Less::GraphStore, IadBot::GraphStore,
  # FolkCoder::GraphStore) add convenience methods and seed loading.
  #
  # Ontology-aware: optionally validates node types and edge types against
  # a declared ontology via load_ontology.
  class GraphStore
    attr_reader :db

    def initialize(db_path = ":memory:")
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      @valid_node_types = nil
      @valid_edge_types = nil
      create_schema
    end

    # --- Ontology validation ---

    # Load valid types from an ontology definition.
    # Once loaded, add_node and add_edge will validate against these types.
    # @param node_types [Array<String>] valid node type strings
    # @param edge_types [Array<String>] valid edge rel_type strings
    def load_ontology(node_types:, edge_types:)
      @valid_node_types = node_types.freeze
      @valid_edge_types = edge_types.freeze
      self
    end

    # --- Node operations ---

    # @param id [String] unique node identifier
    # @param type [String] node type (e.g., "bandh:Product", "fc:Builder")
    # @param label [String] human-readable label
    # @param properties [Hash] arbitrary properties stored as JSON
    def add_node(id:, type:, label: nil, properties: {})
      validate_node_type!(type) if @valid_node_types
      @db.execute(
        "INSERT OR REPLACE INTO nodes (id, type, label, properties) VALUES (?, ?, ?, ?)",
        [id, type, label, JSON.generate(properties)]
      )
    end

    def find_node(id)
      row = @db.get_first_row("SELECT * FROM nodes WHERE id = ?", [id])
      row ? deserialize_node(row) : nil
    end

    def find_nodes(type: nil)
      if type
        @db.execute("SELECT * FROM nodes WHERE type = ?", [type])
      else
        @db.execute("SELECT * FROM nodes")
      end.map { |r| deserialize_node(r) }
    end

    # --- Edge operations ---

    # @param source_id [String] source node id
    # @param target_id [String] target node id
    # @param rel_type [String] relationship type (e.g., "vv:isCompatibleWith")
    # @param properties [Hash] arbitrary edge properties stored as JSON
    def add_edge(source_id:, target_id:, rel_type:, properties: {})
      validate_edge_type!(rel_type) if @valid_edge_types
      @db.execute(
        "INSERT OR REPLACE INTO edges (source_id, target_id, rel_type, properties) VALUES (?, ?, ?, ?)",
        [source_id, target_id, rel_type, JSON.generate(properties)]
      )
    end

    def edges_by_type(rel_type)
      @db.execute("SELECT * FROM edges WHERE rel_type = ?", [rel_type])
    end

    # Find all neighbors of a node, optionally filtered by relationship type.
    # Searches both directions for symmetric properties.
    # @param node_id [String]
    # @param rel_type [String, nil] filter by relationship type
    # @param direction [:both, :outgoing, :incoming]
    # @return [Array<Hash>] neighbor nodes with edge info
    def neighbors(node_id, rel_type: nil, direction: :both)
      conditions = []
      params = []

      case direction
      when :outgoing
        conditions << "e.source_id = ?"
        params << node_id
      when :incoming
        conditions << "e.target_id = ?"
        params << node_id
      else # :both
        conditions << "(e.source_id = ? OR e.target_id = ?)"
        params << node_id << node_id
      end

      if rel_type
        conditions << "e.rel_type = ?"
        params << rel_type
      end

      sql = <<~SQL
        SELECT n.*, e.rel_type, e.properties AS edge_properties
        FROM edges e
        JOIN nodes n ON (
          CASE WHEN e.source_id = '#{node_id}' THEN n.id = e.target_id
               ELSE n.id = e.source_id END
        )
        WHERE #{conditions.join(" AND ")}
      SQL
      @db.execute(sql, params).map do |r|
        {
          node: deserialize_node(r),
          rel_type: r["rel_type"],
          edge_properties: JSON.parse(r["edge_properties"] || "{}")
        }
      end
    end

    # 2-hop traversal: find nodes reachable in 2 hops via given rel_types.
    def two_hop(node_id, rel_types: nil)
      first_hop = neighbors(node_id, rel_type: rel_types&.first)
      seen = Set.new([node_id])
      results = []

      first_hop.each do |hop1|
        hop1_id = hop1[:node]["id"]
        seen << hop1_id

        neighbors(hop1_id, rel_type: rel_types&.last).each do |hop2|
          next if seen.include?(hop2[:node]["id"])
          seen << hop2[:node]["id"]

          results << {
            node: hop2[:node],
            via: hop1[:node]["label"] || hop1[:node]["id"],
            rel_type: hop2[:rel_type]
          }
        end
      end

      results
    end

    # Bounded subgraph exploration from a starting node.
    def subgraph(node_id, max_depth: 2)
      visited = Set.new
      graph = { nodes: [], edges: [] }

      traverse = lambda do |nid, depth|
        return if visited.include?(nid) || depth > max_depth
        visited << nid

        node = find_node(nid)
        return unless node

        graph[:nodes] << node

        @db.execute(
          "SELECT * FROM edges WHERE source_id = ? OR target_id = ?",
          [nid, nid]
        ).each do |edge|
          other_id = edge["source_id"] == nid ? edge["target_id"] : edge["source_id"]
          graph[:edges] << {
            source: edge["source_id"],
            target: edge["target_id"],
            rel_type: edge["rel_type"],
            properties: JSON.parse(edge["properties"] || "{}")
          }
          traverse.call(other_id, depth + 1)
        end
      end

      traverse.call(node_id, 0)
      graph
    end

    # --- Aggregate queries ---

    def node_count
      @db.get_first_value("SELECT COUNT(*) FROM nodes")
    end

    def edge_count
      @db.get_first_value("SELECT COUNT(*) FROM edges")
    end

    def stats
      {
        nodes: node_count,
        edges: edge_count,
        node_types: @db.execute("SELECT type, COUNT(*) as cnt FROM nodes GROUP BY type")
          .each_with_object({}) { |r, h| h[r["type"]] = r["cnt"] },
        edge_types: @db.execute("SELECT rel_type, COUNT(*) as cnt FROM edges GROUP BY rel_type")
          .each_with_object({}) { |r, h| h[r["rel_type"]] = r["cnt"] }
      }
    end

    private

    def create_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS nodes (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          label TEXT,
          properties TEXT
        );

        CREATE TABLE IF NOT EXISTS edges (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_id TEXT NOT NULL,
          target_id TEXT NOT NULL,
          rel_type TEXT NOT NULL,
          properties TEXT,
          UNIQUE(source_id, target_id, rel_type)
        );

        CREATE INDEX IF NOT EXISTS idx_nodes_type ON nodes(type);
        CREATE INDEX IF NOT EXISTS idx_edges_rel_type ON edges(rel_type);
        CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
        CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
      SQL
    end

    def deserialize_node(row)
      {
        "id" => row["id"],
        "type" => row["type"],
        "label" => row["label"],
        "properties" => JSON.parse(row["properties"] || "{}")
      }
    end

    def validate_node_type!(type)
      return if @valid_node_types.include?(type)

      raise ArgumentError,
            "Node type '#{type}' not declared in ontology. Valid: #{@valid_node_types.join(", ")}"
    end

    def validate_edge_type!(rel_type)
      return if @valid_edge_types.include?(rel_type)

      raise ArgumentError,
            "Edge type '#{rel_type}' not declared in ontology. Valid: #{@valid_edge_types.join(", ")}"
    end
  end
end

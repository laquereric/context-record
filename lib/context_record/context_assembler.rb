# frozen_string_literal: true

module ContextRecord
  class ContextAssembler
    def initialize(graph_store:, vector_store: nil)
      @graph = graph_store
      @vector = vector_store
    end

    # Assemble context from graph + optional vector search
    def assemble(node_id: nil, query_text: nil, rel_types: nil, max_depth: 2, top_k: 5)
      structured = node_id ? structured_context(node_id, rel_types: rel_types, max_depth: max_depth) : []
      semantic = (query_text && @vector) ? semantic_context(query_text, top_k: top_k) : []
      format_context(structured, semantic, query_text: query_text)
    end

    def structured_context(node_id, rel_types: nil, max_depth: 2)
      node = @graph.find_node(node_id)
      return [] unless node

      neighbors = @graph.neighbors(node_id)
      neighbors = neighbors.select { |n| rel_types.include?(n[:rel_type]) } if rel_types

      [{ node: node, neighbors: neighbors }]
    end

    def semantic_context(query_text, top_k: 5)
      return [] unless @vector
      @vector.search(query_text, top_k: top_k)
    end

    # Override per domain for custom formatting
    def format_context(structured, semantic, query_text: nil)
      sections = []
      sections << format_structured(structured) unless structured.empty?
      sections << format_semantic(semantic) unless semantic.empty?
      sections << "[USER QUERY]\n#{query_text}" if query_text
      { context: sections.join("\n\n"), sources: build_sources(structured, semantic) }
    end

    private

    def format_structured(entries)
      lines = ["[STRUCTURED DATA]"]
      entries.each do |entry|
        node = entry[:node]
        lines << "#{node['type']}: #{node['label'] || node['id']}"
        lines << "  Properties: #{node['properties'].map { |k, v| "#{k}: #{v}" }.join(', ')}" unless node["properties"].empty?
        entry[:neighbors].each do |n|
          lines << "  #{n[:rel_type]} → #{n[:node]['label'] || n[:node]['id']}"
        end
        lines << ""
      end
      lines.join("\n")
    end

    def format_semantic(entries)
      lines = ["[SEMANTIC DATA]"]
      entries.each do |entry|
        lines << (entry[:text] || entry.to_s).to_s
        lines << ""
      end
      lines.join("\n")
    end

    def build_sources(structured, semantic)
      sources = structured.map { |e| { type: "graph", node_id: e[:node]["id"], neighbors: e[:neighbors].size } }
      sources += semantic.map { |e| { type: "vector", score: e[:score] } } if semantic.any?
      sources
    end
  end
end

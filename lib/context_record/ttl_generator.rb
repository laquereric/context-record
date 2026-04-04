# frozen_string_literal: true

require "json"

module ContextRecord
  class TtlGenerator
    DEFAULT_PREFIXES = {
      "vv" => "https://verticalvertical.net/ns/biological#",
      "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
      "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
      "owl" => "http://www.w3.org/2002/07/owl#",
      "xsd" => "http://www.w3.org/2001/XMLSchema#",
      "skos" => "http://www.w3.org/2004/02/skos/core#"
    }.freeze

    DEFAULT_PROPERTY_MAPPINGS = {}.freeze

    def initialize(prefixes: {}, property_mappings: {})
      @prefixes = DEFAULT_PREFIXES.merge(prefixes)
      @property_mappings = DEFAULT_PROPERTY_MAPPINGS.merge(property_mappings)
    end

    # Generate TTL for a single content item
    def generate(source_id:, content:, node_type:)
      lines = [prefix_block, ""]
      lines << node_to_ttl(source_id, node_type, content)
      lines.join("\n")
    end

    # Generate TTL from arrays of GraphStore nodes and edges
    def generate_from_graph(nodes:, edges:)
      lines = [prefix_block, ""]
      nodes.each { |n| lines << node_to_ttl(n["id"], n["type"], n["properties"] || {}) }
      edges.each { |e| lines << edge_to_ttl(e) }
      lines.join("\n")
    end

    private

    def prefix_block
      @prefixes.map { |prefix, uri| "@prefix #{prefix}: <#{uri}> ." }.join("\n")
    end

    def node_to_ttl(id, type, properties)
      subject = iri(id)
      lines = []
      lines << "#{subject} a #{type} ;"

      # Normalize properties
      if properties.is_a?(Hash)
        props = properties.dup
      else
        props = properties.is_a?(String) ? (JSON.parse(properties) rescue {}) : {}
      end

      # Generate property triples
      predicates = []
      props.each do |key, value|
        predicate = @property_mappings[key] || "vv:hasProperty"
        if predicate == "vv:hasProperty"
          predicates << "  vv:hasProperty [ rdfs:label \"#{escape(key)}\" ; rdf:value #{literal(value)} ]"
        else
          predicates << "  #{predicate} #{literal(value)}"
        end
      end

      if predicates.empty?
        lines[-1] = "#{subject} a #{type} ."
      else
        lines << predicates.join(" ;\n") + " ."
      end

      lines.join("\n")
    end

    def edge_to_ttl(edge)
      source = iri(edge["source_id"])
      target = iri(edge["target_id"])
      rel_type = map_rel_type(edge["rel_type"])

      props = edge["properties"]
      props = JSON.parse(props) if props.is_a?(String)
      props ||= {}

      if props["notes"]
        "#{source} #{rel_type} #{target} .  # #{escape(props["notes"])}"
      else
        "#{source} #{rel_type} #{target} ."
      end
    end

    def iri(id)
      "<urn:vv:#{id}>"
    end

    def literal(value)
      case value
      when String then "\"#{escape(value)}\""
      when Integer then "#{value}"
      when Float then "\"#{value}\"^^xsd:double"
      when TrueClass, FalseClass then "\"#{value}\"^^xsd:boolean"
      when Hash then "\"#{escape(JSON.generate(value))}\""
      when Array then "\"#{escape(value.join(", "))}\""
      else "\"#{escape(value.to_s)}\""
      end
    end

    def escape(str)
      str.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("\n", "\\n")
    end

    def map_rel_type(rel_type)
      case rel_type
      when "is_compatible_with" then "vv:isCompatibleWith"
      when "is_not_compatible_with" then "vv:isNotCompatibleWith"
      when "is_accessory_for" then "vv:isAccessoryFor"
      when "competes_with" then "vv:competesWith"
      when "supersedes" then "vv:supersedes"
      else
        rel_type.include?(":") ? rel_type : "vv:#{rel_type}"
      end
    end
  end
end

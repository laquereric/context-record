# frozen_string_literal: true

require "json"

module ContextRecord
  # A typed JSON-LD node that maps directly to a single JSON-LD value object.
  #
  # ContextPrimitive enforces deterministic serialization: identical inputs
  # produce byte-identical JSON-LD output, which means the same ContextRecord
  # always produces the same token sequence when sent to an LLM.
  #
  # JSON-LD value object spec:
  #   { "@type" => type, "@value" => value }          # typed literal
  #   { "@id" => id }                                  # named node (IRI)
  #   { "@value" => value, "@language" => lang }       # language-tagged string
  #
  # Usage:
  #   p = ContextPrimitive.new(type: "vv:Action", value: "read")
  #   p.to_json_ld  #=> { "@type" => "vv:Action", "@value" => "read" }
  #   p.to_json     #=> '{"@type":"vv:Action","@value":"read"}'
  class ContextPrimitive
    VALID_TYPES = %w[
      vv:Action
      vv:Entity
      vv:Literal
      vv:Identifier
      vv:Relation
      vv:Event
      vv:EvalResult
    ].freeze

    attr_reader :type, :value, :id, :language

    # @param type     [String, nil]  JSON-LD @type — required unless id: is given
    # @param value    [Object, nil]  JSON-LD @value — the payload
    # @param id       [String, nil]  JSON-LD @id — IRI for named nodes
    # @param language [String, nil]  BCP-47 language tag (only valid with string values)
    def initialize(type: nil, value: nil, id: nil, language: nil)
      validate!(type: type, value: value, id: id, language: language)
      @type     = type&.dup&.freeze
      @value    = deep_freeze(value)
      @id       = id&.dup&.freeze
      @language = language&.dup&.freeze
      freeze
    end

    # Returns a deterministic JSON-LD Hash.
    # Keys are always in sorted order for byte-stable serialization.
    # @return [Hash]
    def to_json_ld
      node = {}
      node["@id"]       = @id       if @id
      node["@language"] = @language if @language
      node["@type"]     = @type     if @type
      node["@value"]    = serialize_value(@value) unless @value.nil?
      # Sort by key for deterministic output
      node.sort.to_h
    end

    # Returns a deterministic JSON string (no extra whitespace, sorted keys).
    # @return [String]
    def to_json(*)
      to_json_ld.to_json
    end

    def ==(other)
      other.is_a?(ContextPrimitive) && to_json_ld == other.to_json_ld
    end

    def inspect
      "#<ContextRecord::ContextPrimitive type=#{@type.inspect} value=#{@value.inspect}>"
    end

    private

    def validate!(type:, value:, id:, language:)
      if id.nil? && type.nil? && language.nil?
        raise ArgumentError, "ContextPrimitive requires either type: or id:"
      end

      if language && !value.is_a?(String)
        raise ArgumentError, "language: is only valid with string values"
      end

      if language && type
        raise ArgumentError, "language: and type: are mutually exclusive in JSON-LD"
      end
    end

    def serialize_value(val)
      case val
      when Hash  then val.sort.to_h.transform_values { |v| serialize_value(v) }
      when Array then val.map { |v| serialize_value(v) }
      else val
      end
    end

    def deep_freeze(obj)
      case obj
      when Hash  then obj.each_with_object({}) { |(k, v), h| h[k] = deep_freeze(v) }.freeze
      when Array then obj.map { |v| deep_freeze(v) }.freeze
      else            obj.freeze
      end
    end
  end
end

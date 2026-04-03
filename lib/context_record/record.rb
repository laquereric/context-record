# frozen_string_literal: true

require "securerandom"
require "json"
require_relative "context_primitive"

module ContextRecord
  # A self-describing message envelope that carries complete state.
  # Any Service Node can process a Record without prior context.
  # Implements the REST self-describing messages constraint.
  #
  # Each Record is a JSON-LD document — @context identifies the vocabulary
  # that gives meaning to the payload fields. Records are named nodes in
  # linked data (via @id IRI) and carry a domain-aware @type.
  #
  # Payloads may contain plain Ruby objects or ContextPrimitive instances.
  # When a ContextPrimitive is present, to_json_ld expands it inline,
  # ensuring the full document is deterministically serializable.
  class Record
    VV_CONTEXT = "https://verticalvertical.net/ns/biological#"
    IRI_PREFIX = "urn:vv:record:"

    VALID_ACTIONS = %i[create read update delete list execute evaluate].freeze
    DEFAULT_RDF_TYPE = "vv:Event"

    attr_reader :id, :iri, :rdf_type, :action, :target,
                :payload, :metadata, :timestamp, :context

    def initialize(action:, target:, payload: {}, metadata: {}, context: nil, rdf_type: nil)
      validate_action!(action)
      @id        = SecureRandom.uuid
      @iri       = "#{IRI_PREFIX}#{@id}".freeze
      @rdf_type  = (rdf_type || DEFAULT_RDF_TYPE).to_s.freeze
      @action    = action.to_sym
      @target    = target.to_s.freeze
      @payload   = deep_freeze(payload)
      @metadata  = deep_freeze(metadata)
      @context   = (context || VV_CONTEXT).freeze
      @timestamp = Time.now.utc
      freeze
    end

    # Returns a plain Hash (backward compatible — no @id or @type).
    # Use to_json_ld for a fully expanded JSON-LD document.
    def to_h
      {
        "@context"  => @context,
        "id"        => @id,
        "action"    => @action,
        "target"    => @target,
        "payload"   => @payload,
        "metadata"  => @metadata,
        "timestamp" => @timestamp.iso8601
      }
    end

    # Returns a fully expanded, deterministic JSON-LD document.
    # Includes @id (IRI) and @type for linked data participation.
    # ContextPrimitive values are expanded to their JSON-LD node form.
    # Keys within each hash are sorted for byte-stable output.
    # @return [Hash]
    def to_json_ld
      {
        "@context"  => @context,
        "@id"       => @iri,
        "@type"     => @rdf_type,
        "action"    => @action.to_s,
        "id"        => @id,
        "metadata"  => expand_value(@metadata),
        "payload"   => expand_value(@payload),
        "target"    => @target,
        "timestamp" => @timestamp.iso8601
      }.sort.to_h
    end

    # Deterministic JSON string of the full JSON-LD document.
    # @return [String]
    def to_json(*)
      to_json_ld.to_json
    end

    def json_ld?
      @context != VV_CONTEXT
    end

    # Extract all Record IRIs referenced in metadata.
    # Looks for urn:vv:record:* strings in metadata values.
    # @return [Array<String>] IRIs of linked Records
    def linked_records
      extract_iris(@metadata)
    end

    private

    def validate_action!(action)
      return if VALID_ACTIONS.include?(action.to_sym)

      raise ArgumentError,
            "Invalid action '#{action}'. Must be one of: #{VALID_ACTIONS.join(", ")}"
    end

    def expand_value(obj)
      case obj
      when ContextPrimitive then obj.to_json_ld
      when Hash             then obj.sort.to_h.transform_values { |v| expand_value(v) }
      when Array            then obj.map { |v| expand_value(v) }
      else                       obj
      end
    end

    def deep_freeze(obj)
      case obj
      when Hash  then obj.each_with_object({}) { |(k, v), h| h[k] = deep_freeze(v) }.freeze
      when Array then obj.map { |v| deep_freeze(v) }.freeze
      else            obj.freeze
      end
    end

    def extract_iris(obj)
      case obj
      when String then obj.start_with?(IRI_PREFIX) ? [obj] : []
      when Array  then obj.flat_map { |v| extract_iris(v) }
      when Hash   then obj.values.flat_map { |v| extract_iris(v) }
      else []
      end
    end
  end
end

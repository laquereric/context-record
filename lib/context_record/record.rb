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
  # that gives meaning to the payload fields.
  #
  # Payloads may contain plain Ruby objects or ContextPrimitive instances.
  # When a ContextPrimitive is present, to_json_ld expands it inline,
  # ensuring the full document is deterministically serializable.
  class Record
    VV_CONTEXT = "https://verticalvertical.net/ns/biological#"

    VALID_ACTIONS = %i[create read update delete list execute].freeze

    attr_reader :id, :action, :target, :payload, :metadata, :timestamp, :context

    def initialize(action:, target:, payload: {}, metadata: {}, context: nil)
      validate_action!(action)
      @id        = SecureRandom.uuid
      @action    = action.to_sym
      @target    = target.to_s.freeze
      @payload   = deep_freeze(payload)
      @metadata  = deep_freeze(metadata)
      @context   = (context || VV_CONTEXT).freeze
      @timestamp = Time.now.utc
      freeze
    end

    # Returns a plain Hash (preserves ContextPrimitive objects as-is).
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
    # ContextPrimitive values are expanded to their JSON-LD node form.
    # Keys within each hash are sorted for byte-stable output.
    # @return [Hash]
    def to_json_ld
      {
        "@context"  => @context,
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
  end
end

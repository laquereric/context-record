# frozen_string_literal: true

module ContextRecord
  # Ruby interface to the VV ontology (vv-ontology.ttl).
  #
  # Exposes the classes, relationship properties, and symmetry annotations
  # defined in the Turtle file as Ruby constants and query methods.
  #
  # Usage:
  #   ContextRecord::Ontology.valid_type?("vv:Action")       #=> true
  #   ContextRecord::Ontology.relationship_types              #=> ["vv:isCompatibleWith", ...]
  #   ContextRecord::Ontology.symmetric?("vv:isCompatibleWith") #=> true
  #   ContextRecord::Ontology.symmetric?("vv:supersedes")       #=> false
  module Ontology
    # Classes declared in vv-ontology.ttl (rdfs:Class)
    # The first 7 map 1:1 to ContextPrimitive::VALID_TYPES
    CLASSES = %w[
      vv:Action
      vv:Entity
      vv:Literal
      vv:Identifier
      vv:Relation
      vv:Event
      vv:EvalResult
      vv:DomainEntity
      vv:Taxonomy
    ].freeze

    # Primitive types — the original 7 from ContextPrimitive
    PRIMITIVE_TYPES = %w[
      vv:Action
      vv:Entity
      vv:Literal
      vv:Identifier
      vv:Relation
      vv:Event
      vv:EvalResult
    ].freeze

    # Object properties declared in vv-ontology.ttl (owl:ObjectProperty)
    RELATIONSHIPS = %w[
      vv:isCompatibleWith
      vv:isNotCompatibleWith
      vv:isAccessoryFor
      vv:competesWith
      vv:supersedes
      vv:manufacturedBy
      vv:hasFeature
    ].freeze

    # Linking properties for event chains
    LINK_PROPERTIES = %w[
      vv:relatedTo
      vv:causedBy
    ].freeze

    # Eval properties
    EVAL_PROPERTIES = %w[
      vv:testedProperty
      vv:groundTruth
    ].freeze

    # All object properties
    ALL_PROPERTIES = (RELATIONSHIPS + LINK_PROPERTIES + EVAL_PROPERTIES).freeze

    # Symmetric properties (owl:SymmetricProperty in the ontology)
    SYMMETRIC = %w[
      vv:isCompatibleWith
      vv:isNotCompatibleWith
      vv:competesWith
      vv:relatedTo
    ].freeze

    # Check if a type string is a declared ontology class
    # @param type [String] e.g., "vv:Action"
    # @return [Boolean]
    def self.valid_type?(type)
      CLASSES.include?(type)
    end

    # Check if a type string is a valid context-record primitive type
    # @param type [String] e.g., "vv:Action"
    # @return [Boolean]
    def self.primitive_type?(type)
      PRIMITIVE_TYPES.include?(type)
    end

    # All declared relationship property names
    # @return [Array<String>]
    def self.relationship_types
      RELATIONSHIPS
    end

    # All declared property names (relationships + links + eval)
    # @return [Array<String>]
    def self.all_properties
      ALL_PROPERTIES
    end

    # Check if a relationship is symmetric
    # @param rel_type [String] e.g., "vv:isCompatibleWith"
    # @return [Boolean]
    def self.symmetric?(rel_type)
      SYMMETRIC.include?(rel_type)
    end

    # Path to the ontology Turtle file
    # @return [String]
    def self.ontology_path
      File.expand_path("../../ontology/vv-ontology.ttl", __dir__)
    end

    # Path to the JSON-LD context file
    # @return [String]
    def self.context_path
      File.expand_path("../../ontology/context.jsonld", __dir__)
    end
  end
end

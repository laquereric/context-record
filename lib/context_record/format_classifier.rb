# frozen_string_literal: true

module ContextRecord
  class FormatClassifier
    STRUCTURED_TYPES = %w[application/json application/ld+json].freeze
    NARRATIVE_TYPES = %w[text/plain text/markdown text/html].freeze

    # @param content [String, Hash]
    # @param content_type [String] MIME type
    # @param node_type [String, nil] ontology type if known
    # @return [Symbol] :md, :structured, :both
    def classify(content:, content_type:, node_type: nil)
      signals = []
      signals << content_type_signal(content_type)
      signals << structure_signal(content)
      signals << ontology_signal(node_type) if node_type
      resolve(signals)
    end

    private

    def content_type_signal(ct)
      return :structured if STRUCTURED_TYPES.include?(ct)
      return :md if NARRATIVE_TYPES.include?(ct)
      :unknown
    end

    def structure_signal(content)
      case content
      when Hash
        has_entities = content.key?("id") || content.key?("@type") || content.key?("type")
        has_relationships = content.key?("relationships") || content.key?("edges")
        return :structured if has_entities && has_relationships
        return :both if has_entities
        :md
      when String
        lines = content.lines
        return :md if lines.empty?
        code_lines = lines.count { |l| l.match?(/^\s*[{}\[\]":]/) }
        prose_ratio = 1.0 - (code_lines.to_f / [lines.size, 1].max)
        return :md if prose_ratio > 0.7
        return :structured if prose_ratio < 0.3
        :both
      else
        :structured
      end
    end

    def ontology_signal(node_type)
      return :structured if node_type.to_s.match?(/Product|Entity|Builder|Beneficiary/)
      return :both if node_type.to_s.match?(/Event|Record/)
      :md
    end

    def resolve(signals)
      return :both if signals.include?(:both)
      non_unknown = signals.reject { |s| s == :unknown }
      return :both if non_unknown.empty?
      return non_unknown.first if non_unknown.uniq.size == 1
      :both
    end
  end
end

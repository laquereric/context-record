# frozen_string_literal: true

module ContextRecord
  module EmbeddingProvider
    class Null
      include EmbeddingProvider

      def initialize(dimensions: 768)
        @dimensions = dimensions
      end

      def embed(_text)
        Array.new(@dimensions, 0.0)
      end

      def embed_batch(texts)
        texts.map { |_| Array.new(@dimensions, 0.0) }
      end

      def dimensions
        @dimensions
      end
    end
  end
end

# frozen_string_literal: true

module ContextRecord
  module EmbeddingProvider
    def embed(text)
      raise NotImplementedError, "#{self.class}#embed not implemented"
    end

    def embed_batch(texts)
      texts.map { |t| embed(t) }
    end

    def dimensions
      raise NotImplementedError, "#{self.class}#dimensions not implemented"
    end
  end
end

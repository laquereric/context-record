# frozen_string_literal: true

require "spec_helper"
require "context_record/embedding_provider"
require "context_record/embedding_provider/null"
require "context_record/embedding_provider/ollama"

RSpec.describe ContextRecord::EmbeddingProvider do
  describe ContextRecord::EmbeddingProvider::Null do
    let(:provider) { described_class.new(dimensions: 384) }

    it "returns zero vector of specified dimensions" do
      vec = provider.embed("hello world")
      expect(vec).to be_an(Array)
      expect(vec.size).to eq(384)
      expect(vec.all?(&:zero?)).to be true
    end

    it "returns batch of zero vectors" do
      vecs = provider.embed_batch(["hello", "world"])
      expect(vecs.size).to eq(2)
      vecs.each { |v| expect(v.size).to eq(384) }
    end

    it "reports dimensions" do
      expect(provider.dimensions).to eq(384)
    end

    it "defaults to 768 dimensions" do
      default = described_class.new
      expect(default.dimensions).to eq(768)
    end
  end

  describe ContextRecord::EmbeddingProvider::Ollama do
    it "has correct defaults" do
      ollama = described_class.new
      expect(ollama.dimensions).to eq(768)
    end

    it "accepts custom config" do
      ollama = described_class.new(model: "mxbai-embed-large", url: "http://gpu:11434", dimensions: 1024)
      expect(ollama.dimensions).to eq(1024)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"
require "context_record/embedding_provider"
require "context_record/vector_store"

# Minimal test provider — returns deterministic vectors
class TestEmbeddingProvider
  include ContextRecord::EmbeddingProvider

  def initialize(dimensions: 4)
    @dimensions = dimensions
    @counter = 0
  end

  def embed(text)
    # Generate slightly different vectors based on text hash
    seed = text.bytes.sum
    Array.new(@dimensions) { |i| Math.sin(seed + i).round(6) }
  end

  def dimensions
    @dimensions
  end
end

RSpec.describe ContextRecord::VectorStore do
  let(:provider) { TestEmbeddingProvider.new(dimensions: 4) }
  let(:store) { described_class.new(embedding_provider: provider, dimensions: 4) }

  describe "#add and #count" do
    it "adds a document" do
      store.add(id: "doc-1", text: "hello world")
      expect(store.count).to eq(1)
    end

    it "updates existing document" do
      store.add(id: "doc-1", text: "hello")
      store.add(id: "doc-1", text: "updated hello")
      expect(store.count).to eq(1)
    end
  end

  describe "#add_batch" do
    it "adds multiple documents" do
      store.add_batch([
        { id: "a", text: "alpha" },
        { id: "b", text: "beta" },
        { id: "c", text: "gamma" }
      ])
      expect(store.count).to eq(3)
    end

    it "handles empty batch" do
      store.add_batch([])
      expect(store.count).to eq(0)
    end
  end

  describe "#search" do
    before do
      store.add_batch([
        { id: "d1", text: "microphone audio recording", metadata: { type: "product" } },
        { id: "d2", text: "camera lens photography", metadata: { type: "product" } },
        { id: "d3", text: "audio interface preamp", metadata: { type: "product" } }
      ])
    end

    it "returns results" do
      results = store.search("microphone", top_k: 3)
      expect(results).to be_an(Array)
      expect(results.size).to eq(3)
    end

    it "returns expected structure" do
      results = store.search("audio", top_k: 1)
      result = results.first
      expect(result).to have_key(:text)
      expect(result).to have_key(:score)
      expect(result).to have_key(:metadata)
    end

    it "includes metadata" do
      results = store.search("test", top_k: 1)
      expect(results.first[:metadata]).to be_a(Hash)
    end

    it "respects top_k" do
      results = store.search("test", top_k: 2)
      expect(results.size).to be <= 2
    end
  end

  describe "#dimensions" do
    it "reports embedding dimensions" do
      expect(store.dimensions).to eq(4)
    end

    it "defaults from provider" do
      s = described_class.new(embedding_provider: provider)
      expect(s.dimensions).to eq(4)
    end
  end
end

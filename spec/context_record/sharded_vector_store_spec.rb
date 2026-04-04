# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "context_record/embedding_provider"
require "context_record/embedding_provider/null"
require "context_record/vector_store"
require "context_record/sharded_vector_store"

RSpec.describe ContextRecord::ShardedVectorStore do
  let(:provider) { ContextRecord::EmbeddingProvider::Null.new(dimensions: 4) }
  let(:base_path) { Dir.mktmpdir("sharded_test") }
  let(:store) do
    described_class.new(
      base_path: base_path,
      embedding_provider: provider,
      max_open: 3
    )
  end

  after do
    store.close_all
    FileUtils.rm_rf(base_path)
  end

  describe "#add and #count" do
    it "adds documents to specific shards" do
      store.add(id: "a", text: "alpha", shard: "cat1")
      store.add(id: "b", text: "beta", shard: "cat2")
      expect(store.count(shard: "cat1")).to eq(1)
      expect(store.count(shard: "cat2")).to eq(1)
    end

    it "creates nested shard directories" do
      store.add(id: "a", text: "alpha", shard: "cameras/lenses")
      expect(File.exist?(File.join(base_path, "cameras/lenses.sqlite3"))).to be true
    end
  end

  describe "#add_batch" do
    it "adds multiple documents to a shard" do
      items = [
        { id: "a", text: "alpha" },
        { id: "b", text: "beta" },
        { id: "c", text: "gamma" }
      ]
      store.add_batch(items, shard: "batch_test")
      expect(store.count(shard: "batch_test")).to eq(3)
    end

    it "handles empty batch" do
      store.add_batch([], shard: "empty")
      expect(store.shard_names).not_to include("empty")
    end
  end

  describe "#search" do
    before do
      store.add_batch([
        { id: "m1", text: "dynamic microphone" },
        { id: "m2", text: "condenser microphone" }
      ], shard: "pro_audio/mics")

      store.add_batch([
        { id: "c1", text: "mirrorless camera" },
        { id: "c2", text: "dslr camera" }
      ], shard: "cameras/bodies")
    end

    it "searches within a single shard" do
      results = store.search("microphone", shard: "pro_audio/mics", top_k: 2)
      expect(results.size).to eq(2)
      results.each { |r| expect(r).to have_key(:text) }
    end

    it "does not cross shards" do
      results = store.search("camera", shard: "pro_audio/mics", top_k: 5)
      texts = results.map { |r| r[:text] }
      expect(texts).not_to include("mirrorless camera")
    end
  end

  describe "#search_multi" do
    before do
      store.add(id: "a", text: "audio interface", shard: "audio")
      store.add(id: "b", text: "camera lens", shard: "cameras")
      store.add(id: "c", text: "video monitor", shard: "video")
    end

    it "searches across multiple shards" do
      results = store.search_multi("equipment", shards: ["audio", "cameras", "video"], top_k: 3)
      expect(results.size).to eq(3)
    end

    it "respects top_k across merged results" do
      results = store.search_multi("equipment", shards: ["audio", "cameras", "video"], top_k: 2)
      expect(results.size).to eq(2)
    end
  end

  describe "#shard_names" do
    it "lists all shards on disk" do
      store.add(id: "a", text: "alpha", shard: "cat1")
      store.add(id: "b", text: "beta", shard: "nested/cat2")
      names = store.shard_names
      expect(names).to include("cat1")
      expect(names).to include("nested/cat2")
    end
  end

  describe "#shard_stats" do
    it "returns per-shard counts" do
      store.add_batch([{ id: "a", text: "x" }, { id: "b", text: "y" }], shard: "s1")
      store.add(id: "c", text: "z", shard: "s2")
      stats = store.shard_stats
      expect(stats["s1"][:count]).to eq(2)
      expect(stats["s2"][:count]).to eq(1)
    end
  end

  describe "#total_count" do
    it "sums across all shards" do
      store.add_batch([{ id: "a", text: "x" }, { id: "b", text: "y" }], shard: "s1")
      store.add(id: "c", text: "z", shard: "s2")
      expect(store.total_count).to eq(3)
    end
  end

  describe "LRU cache" do
    it "limits open connections" do
      store.add(id: "a", text: "x", shard: "s1")
      store.add(id: "b", text: "y", shard: "s2")
      store.add(id: "c", text: "z", shard: "s3")
      expect(store.open_shards).to eq(3)

      # Adding a 4th shard should evict the LRU (s1)
      store.add(id: "d", text: "w", shard: "s4")
      expect(store.open_shards).to eq(3)
    end

    it "keeps recently accessed shards open" do
      store.add(id: "a", text: "x", shard: "s1")
      store.add(id: "b", text: "y", shard: "s2")
      store.add(id: "c", text: "z", shard: "s3")

      # Access s1 again to make it recently used
      store.search("x", shard: "s1", top_k: 1)

      # s2 should be evicted (LRU), not s1
      store.add(id: "d", text: "w", shard: "s4")
      expect(store.open_shards).to eq(3)

      # s1 should still work (was re-accessed)
      results = store.search("x", shard: "s1", top_k: 1)
      expect(results).not_to be_empty
    end
  end

  describe "#close_all" do
    it "closes all connections" do
      store.add(id: "a", text: "x", shard: "s1")
      store.add(id: "b", text: "y", shard: "s2")
      store.close_all
      expect(store.open_shards).to eq(0)
    end
  end
end

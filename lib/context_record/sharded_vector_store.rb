# frozen_string_literal: true

require "fileutils"
require "json"

module ContextRecord
  # Category-sharded vector storage for large catalogs.
  #
  # Each shard is a separate SQLite file backed by VectorStore.
  # Designed for 400K+ products where flat-scan sqlite-vec in a single
  # file is too slow. Category shards keep search under 5ms.
  #
  # Usage:
  #   store = ShardedVectorStore.new(
  #     base_path: "data/vectors/bandh",
  #     embedding_provider: provider
  #   )
  #   store.add(id: "canon-r5#0", text: "...", shard: "cameras/mirrorless")
  #   store.search("Canon lens", shard: "cameras/lenses", top_k: 10)
  class ShardedVectorStore
    attr_reader :base_path, :dimensions

    # @param base_path [String] root directory for shard SQLite files
    # @param embedding_provider [EmbeddingProvider] for generating embeddings
    # @param dimensions [Integer] embedding dimensions (default from provider)
    # @param max_open [Integer] max number of open SQLite connections (LRU cache)
    def initialize(base_path:, embedding_provider:, dimensions: nil, max_open: 10)
      @base_path = base_path
      @provider = embedding_provider
      @dimensions = dimensions || embedding_provider.dimensions
      @max_open = max_open
      @shards = {}       # shard_name => VectorStore
      @access_order = []  # LRU tracking: most recent at end
      FileUtils.mkdir_p(base_path)
    end

    # Add a single document to a shard
    def add(id:, text:, metadata: {}, shard:)
      store = get_shard(shard)
      store.add(id: id, text: text, metadata: metadata.merge("shard" => shard))
    end

    # Add multiple documents to a single shard
    def add_batch(items, shard:)
      return if items.empty?

      store = get_shard(shard)
      enriched = items.map do |item|
        item.merge(metadata: (item[:metadata] || {}).merge("shard" => shard))
      end
      store.add_batch(enriched)
    end

    # Search within a single shard
    # @param query_text [String]
    # @param shard [String] shard name
    # @param top_k [Integer]
    # @return [Array<Hash>] [{text:, score:, metadata:}]
    def search(query_text, shard:, top_k: 5)
      store = get_shard(shard)
      store.search(query_text, top_k: top_k)
    end

    # Search across multiple shards, merge and re-rank top-k
    # @param query_text [String]
    # @param shards [Array<String>] shard names to search
    # @param top_k [Integer]
    # @return [Array<Hash>] [{text:, score:, metadata:}]
    def search_multi(query_text, shards:, top_k: 5)
      all_results = shards.flat_map do |shard_name|
        search(query_text, shard: shard_name, top_k: top_k)
      end
      all_results.sort_by { |r| -r[:score] }.first(top_k)
    end

    # Count documents in a specific shard
    def count(shard:)
      store = get_shard(shard)
      store.count
    end

    # Total documents across all shards on disk
    def total_count
      shard_names.sum { |name| count(shard: name) }
    end

    # List all shard names (from directory structure)
    def shard_names
      Dir.glob(File.join(@base_path, "**/*.sqlite3")).map do |path|
        path.sub("#{@base_path}/", "").sub(".sqlite3", "")
      end.sort
    end

    # Per-shard stats
    def shard_stats
      shard_names.each_with_object({}) do |name, h|
        h[name] = { count: count(shard: name) }
      end
    end

    # Number of currently open shard connections
    def open_shards
      @shards.size
    end

    # Close all open shard connections
    def close_all
      @shards.each_value { |store| store.db.close rescue nil }
      @shards.clear
      @access_order.clear
    end

    private

    def get_shard(shard_name)
      if @shards.key?(shard_name)
        # Move to end of access order (most recently used)
        @access_order.delete(shard_name)
        @access_order.push(shard_name)
        return @shards[shard_name]
      end

      # Evict LRU if at capacity
      evict_lru if @shards.size >= @max_open

      # Create or open shard
      db_path = shard_path(shard_name)
      FileUtils.mkdir_p(File.dirname(db_path))

      store = VectorStore.new(
        db_path: db_path,
        embedding_provider: @provider,
        dimensions: @dimensions
      )

      @shards[shard_name] = store
      @access_order.push(shard_name)
      store
    end

    def shard_path(shard_name)
      File.join(@base_path, "#{shard_name}.sqlite3")
    end

    def evict_lru
      return if @access_order.empty?

      lru_name = @access_order.shift
      store = @shards.delete(lru_name)
      store&.db&.close rescue nil
    end
  end
end

# frozen_string_literal: true

require "json"
require "fileutils"

module ContextRecord
  # 4-stage ingestion pipeline: Store → TTL → Embed → Format.
  #
  # Accepts any content, stores the original on disk, generates Turtle triples,
  # creates sqlite-vec embeddings, and decides whether to write Markdown.
  #
  # Returns a ContextRecord::Record envelope with full provenance.
  #
  # Usage:
  #   pipeline = IngestPipeline.new(
  #     graph_store: store,
  #     base_path: "data/knowledge",
  #     embedding_provider: provider
  #   )
  #   result = pipeline.ingest(content: data, source_id: "products/canon-r5")
  class IngestPipeline
    attr_reader :graph_store, :base_path, :vector_store, :ttl_generator, :format_classifier

    # @param graph_store [ContextRecord::GraphStore] any subclass
    # @param base_path [String] root directory for file output
    # @param embedding_provider [EmbeddingProvider] for generating embeddings
    # @param ttl_generator [TtlGenerator] optional, creates default if nil
    # @param format_classifier [FormatClassifier] optional, creates default if nil
    # @param vector_store [VectorStore] optional, creates one from provider if nil
    def initialize(graph_store:, base_path:, embedding_provider:,
                   ttl_generator: nil, format_classifier: nil, vector_store: nil)
      @graph_store = graph_store
      @base_path = base_path
      @provider = embedding_provider
      @ttl_generator = ttl_generator || TtlGenerator.new
      @format_classifier = format_classifier || FormatClassifier.new
      @vector_store = vector_store || VectorStore.new(
        embedding_provider: embedding_provider,
        dimensions: embedding_provider.dimensions
      )
    end

    # Ingest a single content item through all 4 stages.
    #
    # @param content [String, Hash] raw content
    # @param source_id [String] canonical identifier (e.g., "products/canon-r5")
    # @param content_type [String, nil] MIME type (auto-detected if nil)
    # @param metadata [Hash] optional provenance metadata
    # @return [ContextRecord::Record] provenance envelope
    def ingest(content:, source_id:, content_type: nil, metadata: {})
      content_type ||= detect_content_type(content)
      timings = {}

      # Stage 1: Store original
      original_path = timed(timings, :store) do
        store_original(content, source_id, content_type)
      end

      # Stage 2: Generate TTL
      parsed = parse_content(content, content_type)
      node_type = infer_node_type(parsed, metadata)
      ttl_content = timed(timings, :ttl) do
        @ttl_generator.generate(source_id: source_id, content: parsed, node_type: node_type)
      end
      ttl_path = write_file("ttl", source_id, ".ttl", ttl_content)

      # Stage 3: Embed
      chunks = chunkify(content, source_id)
      embedding_count = timed(timings, :embed) do
        @vector_store.add_batch(chunks)
        chunks.size
      end

      # Stage 4: Format decision
      format_decision = timed(timings, :format) do
        @format_classifier.classify(content: parsed, content_type: content_type, node_type: node_type)
      end
      md_path = nil
      if format_decision == :md || format_decision == :both
        md_path = write_markdown(source_id, parsed, node_type, ttl_path)
      end

      # Return provenance Record
      Record.new(
        action: :create,
        target: source_id,
        rdf_type: "vv:IngestEvent",
        payload: {
          "original_path" => original_path,
          "ttl_path" => ttl_path,
          "md_path" => md_path,
          "format_decision" => format_decision.to_s,
          "embedding_count" => embedding_count
        },
        metadata: metadata.merge(
          "stages" => %w[store ttl embed format],
          "timings" => timings.transform_values { |v| v.round(4) }
        )
      )
    end

    # Batch ingest multiple items.
    # @param items [Array<Hash>] each with :content, :source_id, and optional :content_type, :metadata
    # @return [Array<ContextRecord::Record>]
    def ingest_batch(items)
      items.map do |item|
        ingest(
          content: item[:content],
          source_id: item[:source_id],
          content_type: item[:content_type],
          metadata: item[:metadata] || {}
        )
      end
    end

    private

    # --- Stage 1: Store original ---

    def store_original(content, source_id, content_type)
      ext = extension_for(content_type)
      path = File.join(@base_path, "originals", "#{source_id}#{ext}")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, serialize_content(content))

      # Also add to GraphStore as a provenance node
      @graph_store.add_node(
        id: source_id,
        type: "vv:IngestedContent",
        label: source_id,
        properties: {
          "content_type" => content_type,
          "path" => path,
          "ingested_at" => Time.now.utc.iso8601
        }
      )

      path
    end

    # --- Stage 4: Write Markdown ---

    def write_markdown(source_id, parsed, node_type, ttl_path)
      md_path = File.join(@base_path, "md", "#{source_id}.md")
      FileUtils.mkdir_p(File.dirname(md_path))

      lines = []
      lines << "# #{source_id.split("/").last}"
      lines << ""
      lines << "**Type:** #{node_type}"
      lines << "**Ingested:** #{Time.now.utc.iso8601}"
      lines << ""

      if parsed.is_a?(Hash) && !parsed.empty?
        lines << "## Properties"
        parsed.each do |key, value|
          display = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
          lines << "- **#{key}:** #{display}"
        end
        lines << ""
      elsif parsed.is_a?(String) && !parsed.empty?
        lines << "## Content"
        lines << parsed
        lines << ""
      end

      lines << "---"
      lines << "*Structured data: [#{File.basename(ttl_path)}](#{ttl_path})*"

      File.write(md_path, lines.join("\n"))
      md_path
    end

    # --- Helpers ---

    def detect_content_type(content)
      case content
      when Hash then "application/json"
      when String
        content.strip.start_with?("{", "[") ? "application/json" : "text/plain"
      else "application/octet-stream"
      end
    end

    def parse_content(content, content_type)
      case content
      when Hash then content
      when String
        if content_type&.include?("json")
          JSON.parse(content) rescue content
        else
          content
        end
      else content
      end
    end

    def infer_node_type(parsed, metadata)
      return metadata["node_type"] if metadata["node_type"]
      return metadata[:node_type] if metadata[:node_type]

      if parsed.is_a?(Hash)
        return parsed["@type"] if parsed["@type"]
        return parsed["type"] if parsed["type"]
      end

      "vv:DomainEntity"
    end

    def extension_for(content_type)
      case content_type
      when "application/json", "application/ld+json" then ".json"
      when "text/markdown" then ".md"
      when "text/html" then ".html"
      when "text/turtle" then ".ttl"
      else ".txt"
      end
    end

    def serialize_content(content)
      case content
      when Hash, Array then JSON.pretty_generate(content)
      else content.to_s
      end
    end

    def chunkify(content, source_id)
      text = case content
             when Hash then JSON.generate(content)
             when String then content
             else content.to_s
             end

      # For short content, single chunk
      if text.length <= 2000
        return [{ id: "#{source_id}#chunk-0", text: text, metadata: { source_id: source_id, chunk: 0 } }]
      end

      # Sliding window: ~500 chars with 125 overlap
      chunks = []
      window = 500
      overlap = 125
      pos = 0
      idx = 0

      while pos < text.length
        chunk_text = text[pos, window]
        chunks << { id: "#{source_id}#chunk-#{idx}", text: chunk_text, metadata: { source_id: source_id, chunk: idx } }
        pos += (window - overlap)
        idx += 1
      end

      chunks
    end

    def write_file(subdir, source_id, ext, content)
      path = File.join(@base_path, subdir, "#{source_id}#{ext}")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    def timed(timings, stage)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      timings[stage.to_s] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      result
    end
  end
end

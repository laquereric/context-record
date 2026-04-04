# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "context_record/embedding_provider"
require "context_record/embedding_provider/null"
require "context_record/vector_store"
require "context_record/ttl_generator"
require "context_record/format_classifier"
require "context_record/ingest_pipeline"

RSpec.describe ContextRecord::IngestPipeline do
  let(:graph_store) { ContextRecord::GraphStore.new }
  let(:provider) { ContextRecord::EmbeddingProvider::Null.new(dimensions: 4) }
  let(:base_path) { Dir.mktmpdir("ingest_test") }
  let(:pipeline) do
    described_class.new(
      graph_store: graph_store,
      base_path: base_path,
      embedding_provider: provider
    )
  end

  after { FileUtils.rm_rf(base_path) }

  describe "#ingest" do
    context "with JSON content" do
      let(:content) { { "id" => "test-product", "type" => "bandh:Product", "name" => "Test Widget", "price" => 99 } }

      it "returns a Record with action :create" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        expect(result).to be_a(ContextRecord::Record)
        expect(result.action).to eq(:create)
        expect(result.rdf_type).to eq("vv:IngestEvent")
        expect(result.target).to eq("products/test-widget")
      end

      it "stores the original file" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        original_path = result.payload["original_path"]
        expect(File.exist?(original_path)).to be true
        stored = JSON.parse(File.read(original_path))
        expect(stored["name"]).to eq("Test Widget")
      end

      it "generates a TTL file" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        ttl_path = result.payload["ttl_path"]
        expect(File.exist?(ttl_path)).to be true
        ttl = File.read(ttl_path)
        expect(ttl).to include("@prefix vv:")
        expect(ttl).to include("<urn:vv:products/test-widget>")
      end

      it "creates embeddings" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        expect(result.payload["embedding_count"]).to be >= 1
        expect(pipeline.vector_store.count).to be >= 1
      end

      it "adds a provenance node to the graph store" do
        pipeline.ingest(content: content, source_id: "products/test-widget")
        node = graph_store.find_node("products/test-widget")
        expect(node).not_to be_nil
        expect(node["type"]).to eq("vv:IngestedContent")
      end

      it "includes timings in metadata" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        timings = result.metadata["timings"]
        expect(timings).to have_key("store")
        expect(timings).to have_key("ttl")
        expect(timings).to have_key("embed")
        expect(timings).to have_key("format")
      end

      it "records stages in metadata" do
        result = pipeline.ingest(content: content, source_id: "products/test-widget")
        expect(result.metadata["stages"]).to eq(%w[store ttl embed format])
      end
    end

    context "with text content" do
      let(:prose) do
        "The Shure SM7B is a legendary dynamic microphone used in podcasting and music production. " \
        "It pairs well with the Focusrite Scarlett 2i2 audio interface via XLR connection."
      end

      it "classifies prose and writes markdown" do
        result = pipeline.ingest(content: prose, source_id: "notes/sm7b-review", content_type: "text/plain")
        expect(%w[md both]).to include(result.payload["format_decision"])
        expect(result.payload["md_path"]).not_to be_nil
        expect(File.exist?(result.payload["md_path"])).to be true
      end

      it "markdown includes content" do
        result = pipeline.ingest(content: prose, source_id: "notes/sm7b-review", content_type: "text/plain")
        md = File.read(result.payload["md_path"])
        expect(md).to include("# sm7b-review")
        expect(md).to include("Shure SM7B")
      end
    end

    context "with metadata" do
      it "passes metadata through to the Record" do
        result = pipeline.ingest(
          content: { "id" => "x" },
          source_id: "test/meta",
          metadata: { "domain" => "bandh", "origin" => "seed" }
        )
        expect(result.metadata["domain"]).to eq("bandh")
        expect(result.metadata["origin"]).to eq("seed")
      end

      it "infers node_type from metadata" do
        result = pipeline.ingest(
          content: { "name" => "Test" },
          source_id: "test/typed",
          metadata: { "node_type" => "bandh:Product" }
        )
        ttl = File.read(result.payload["ttl_path"])
        expect(ttl).to include("bandh:Product")
      end
    end

    context "format decisions" do
      it "structured JSON with entities+relationships → no md file" do
        content = { "id" => "x", "type" => "Product", "relationships" => [{ "target" => "y" }] }
        result = pipeline.ingest(content: content, source_id: "test/struct")
        expect(result.payload["format_decision"]).to eq("structured")
        expect(result.payload["md_path"]).to be_nil
      end

      it "JSON with entities but no relationships → both" do
        content = { "id" => "x", "type" => "Product", "name" => "Widget" }
        result = pipeline.ingest(content: content, source_id: "test/both")
        expect(result.payload["format_decision"]).to eq("both")
        expect(result.payload["md_path"]).not_to be_nil
      end
    end
  end

  describe "#ingest_batch" do
    it "ingests multiple items" do
      items = [
        { content: { "id" => "a" }, source_id: "batch/a" },
        { content: { "id" => "b" }, source_id: "batch/b" },
        { content: "plain text", source_id: "batch/c", content_type: "text/plain" }
      ]
      results = pipeline.ingest_batch(items)
      expect(results.size).to eq(3)
      results.each { |r| expect(r).to be_a(ContextRecord::Record) }
    end
  end

  describe "chunking" do
    it "creates single chunk for short content" do
      result = pipeline.ingest(content: "short text", source_id: "test/short")
      expect(result.payload["embedding_count"]).to eq(1)
    end

    it "creates multiple chunks for long content" do
      long_text = "word " * 1000  # ~5000 chars
      result = pipeline.ingest(content: long_text, source_id: "test/long")
      expect(result.payload["embedding_count"]).to be > 1
    end
  end
end

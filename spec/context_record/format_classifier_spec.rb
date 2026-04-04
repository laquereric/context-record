# frozen_string_literal: true

require "spec_helper"
require "context_record/format_classifier"

RSpec.describe ContextRecord::FormatClassifier do
  let(:classifier) { described_class.new }

  describe "#classify" do
    context "JSON content" do
      it "classifies JSON with entities and relationships as :structured" do
        result = classifier.classify(
          content: { "id" => "test", "type" => "Product", "relationships" => [] },
          content_type: "application/json"
        )
        expect(result).to eq(:structured)
      end

      it "classifies JSON with entities but no relationships as :both" do
        result = classifier.classify(
          content: { "id" => "test", "type" => "Product" },
          content_type: "application/json"
        )
        expect(result).to eq(:both)
      end

      it "classifies JSON-LD as :structured" do
        result = classifier.classify(
          content: { "@type" => "Product", "relationships" => [] },
          content_type: "application/ld+json"
        )
        expect(result).to eq(:structured)
      end
    end

    context "text content" do
      it "classifies prose as :md" do
        prose = "This is a long paragraph of text about microphones and audio equipment. " \
                "It discusses various brands and their compatibility with different interfaces."
        result = classifier.classify(content: prose, content_type: "text/plain")
        expect(result).to eq(:md)
      end

      it "classifies markdown as :md" do
        md = "# Meeting Notes\n\nWe discussed the new product lineup.\n\n- Item one\n- Item two\n"
        result = classifier.classify(content: md, content_type: "text/markdown")
        expect(result).to eq(:md)
      end

      it "classifies code-heavy text as :both when content_type is text/plain" do
        code = "{\n  \"id\": \"test\",\n  \"type\": \"Product\",\n  \"name\": \"Widget\"\n}"
        result = classifier.classify(content: code, content_type: "text/plain")
        expect(result).to eq(:both)
      end
    end

    context "with ontology type" do
      it "biases toward :structured for Product types" do
        result = classifier.classify(
          content: "A product description",
          content_type: "text/plain",
          node_type: "bandh:Product"
        )
        expect(result).to eq(:both)
      end

      it "biases toward :both for Event types" do
        result = classifier.classify(
          content: { "id" => "evt-1", "type" => "Event" },
          content_type: "application/json",
          node_type: "vv:Event"
        )
        expect(result).to eq(:both)
      end

      it "biases toward :structured for Entity types" do
        result = classifier.classify(
          content: { "id" => "e1", "type" => "Entity", "relationships" => [] },
          content_type: "application/json",
          node_type: "vv:Entity"
        )
        expect(result).to eq(:structured)
      end
    end

    context "edge cases" do
      it "returns :md for empty string" do
        result = classifier.classify(content: "", content_type: "text/plain")
        expect(result).to eq(:md)
      end

      it "returns :structured for non-string non-hash content" do
        result = classifier.classify(content: [1, 2, 3], content_type: "application/json")
        expect(result).to eq(:structured)
      end

      it "returns :md for unknown content type with prose content" do
        result = classifier.classify(content: "some text", content_type: "application/octet-stream")
        expect(result).to eq(:md)
      end
    end
  end
end

# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ContextRecord
  module EmbeddingProvider
    class Ollama
      include EmbeddingProvider

      DEFAULT_MODEL = "nomic-embed-text"
      DEFAULT_URL = "http://localhost:11434"
      DEFAULT_DIMENSIONS = 768

      def initialize(model: DEFAULT_MODEL, url: DEFAULT_URL, dimensions: DEFAULT_DIMENSIONS)
        @model = model
        @url = url
        @dimensions = dimensions
      end

      def embed(text)
        response = post_embed([text])
        response.first
      end

      def embed_batch(texts)
        post_embed(texts)
      end

      def dimensions
        @dimensions
      end

      private

      def post_embed(texts)
        uri = URI("#{@url}/api/embed")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = JSON.generate({ model: @model, input: texts })

        response = http.request(request)
        raise "Ollama embed failed (#{response.code}): #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(response.body)
        parsed["embeddings"]
      end
    end
  end
end

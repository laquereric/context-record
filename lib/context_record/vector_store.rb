# frozen_string_literal: true

require "json"
require "sqlite3"
require "sqlite_vec"

module ContextRecord
  class VectorStore
    attr_reader :db, :dimensions

    # @param db_path [String] path to SQLite database (":memory:" for in-memory)
    # @param embedding_provider [EmbeddingProvider] provider for generating embeddings
    # @param dimensions [Integer] embedding vector dimensions
    def initialize(db_path: ":memory:", embedding_provider:, dimensions: nil)
      @provider = embedding_provider
      @dimensions = dimensions || embedding_provider.dimensions
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true
      load_extension
      create_schema
    end

    # Add a single document
    def add(id:, text:, metadata: {})
      embedding = @provider.embed(text)
      insert_document(id, text, metadata, embedding)
    end

    # Add multiple documents (batches embedding call)
    def add_batch(items)
      return if items.empty?

      texts = items.map { |i| i[:text] }
      embeddings = @provider.embed_batch(texts)
      @db.transaction do
        items.each_with_index do |item, idx|
          insert_document(item[:id], item[:text], item[:metadata] || {}, embeddings[idx])
        end
      end
    end

    # Semantic search — compatible with ContextAssembler interface
    # @param query_text [String]
    # @param top_k [Integer]
    # @return [Array<Hash>] [{text:, score:, metadata:}]
    def search(query_text, top_k: 5)
      query_embedding = @provider.embed(query_text)
      blob = serialize_vector(query_embedding)

      rows = @db.execute(<<~SQL, [blob, top_k])
        SELECT d.id, d.text, d.metadata, v.distance
        FROM vec_documents_vec v
        JOIN vec_documents d ON d.rowid = v.rowid
        WHERE v.embedding MATCH ? AND k = ?
        ORDER BY v.distance
      SQL

      rows.map do |r|
        {
          text: r["text"],
          score: 1.0 / (1.0 + r["distance"]),
          metadata: JSON.parse(r["metadata"] || "{}")
        }
      end
    end

    # Number of indexed documents
    def count
      @db.get_first_value("SELECT COUNT(*) FROM vec_documents")
    end

    private

    def load_extension
      @db.enable_load_extension(true)
      SqliteVec.load(@db)
      @db.enable_load_extension(false)
    end

    def create_schema
      @db.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS vec_documents (
          id TEXT PRIMARY KEY,
          text TEXT NOT NULL,
          metadata TEXT
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS vec_documents_vec USING vec0(
          embedding float[#{@dimensions}]
        );
      SQL
    end

    def insert_document(id, text, metadata, embedding)
      existing = @db.get_first_row("SELECT rowid FROM vec_documents WHERE id = ?", [id])

      if existing
        rowid = existing["rowid"]
        @db.execute("UPDATE vec_documents SET text = ?, metadata = ? WHERE id = ?",
                    [text, JSON.generate(metadata), id])
        @db.execute("DELETE FROM vec_documents_vec WHERE rowid = ?", [rowid])
        @db.execute("INSERT INTO vec_documents_vec (rowid, embedding) VALUES (?, ?)",
                    [rowid, serialize_vector(embedding)])
      else
        @db.execute("INSERT INTO vec_documents (id, text, metadata) VALUES (?, ?, ?)",
                    [id, text, JSON.generate(metadata)])
        rowid = @db.last_insert_row_id
        @db.execute("INSERT INTO vec_documents_vec (rowid, embedding) VALUES (?, ?)",
                    [rowid, serialize_vector(embedding)])
      end
    end

    def serialize_vector(vec)
      vec.pack("f*")
    end
  end
end

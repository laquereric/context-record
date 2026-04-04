# frozen_string_literal: true

require_relative "context_record/version"
require_relative "context_record/ontology"
require_relative "context_record/context_primitive"
require_relative "context_record/record"
require_relative "context_record/graph_store"
require_relative "context_record/context_assembler"
require_relative "context_record/embedding_provider"
require_relative "context_record/embedding_provider/null"
require_relative "context_record/embedding_provider/ollama"
require_relative "context_record/vector_store"
require_relative "context_record/sharded_vector_store"
require_relative "context_record/ttl_generator"
require_relative "context_record/format_classifier"
require_relative "context_record/ingest_pipeline"
require_relative "context_record/llm_client"
require_relative "context_record/research_agent"

# ContextRecord — typed JSON-LD message envelope and primitive.
#
# Quick start:
#   require "context_record"
#
#   p = ContextRecord::ContextPrimitive.new(type: "vv:Action", value: "read")
#   r = ContextRecord::Record.new(action: :read, target: "users", payload: { filter: p })
#   r.to_json_ld  # deterministic JSON-LD Hash
module ContextRecord
end

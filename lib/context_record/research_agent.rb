# frozen_string_literal: true

module ContextRecord
  # Base research agent — uses local LLM + GraphStore + VectorStore for
  # domain-specific research with RAG context assembly.
  #
  # Domain subclasses override system_prompt and add domain-specific logic.
  #
  # Usage:
  #   agent = ResearchAgent.new(
  #     graph_store: store,
  #     vector_store: vector_store,
  #     pipeline: pipeline,
  #     conductor: LlmClient.from_env(role: :conductor),
  #     sme: LlmClient.from_env(role: :sme),
  #     system_prompt: "You are a product expert..."
  #   )
  #   result = agent.research("What lens fits the Canon R5?")
  class ResearchAgent
    attr_reader :graph_store, :vector_store, :pipeline

    # @param graph_store [GraphStore] domain knowledge graph
    # @param vector_store [VectorStore, ShardedVectorStore, nil] semantic search
    # @param pipeline [IngestPipeline, nil] for storing discoveries
    # @param conductor [LlmClient] fast routing model
    # @param sme [LlmClient] deep reasoning model
    # @param system_prompt [String] domain-specific system prompt
    def initialize(graph_store:, vector_store: nil, pipeline: nil,
                   conductor: nil, sme: nil, system_prompt: DEFAULT_PROMPT)
      @graph_store = graph_store
      @vector_store = vector_store
      @pipeline = pipeline
      @conductor = conductor || LlmClient.from_env(role: :conductor)
      @sme = sme || LlmClient.from_env(role: :sme)
      @system_prompt = system_prompt
      @assembler = ContextAssembler.new(graph_store: graph_store, vector_store: vector_store)
    end

    DEFAULT_PROMPT = "You are a knowledgeable research assistant. Answer questions using the provided context. Cite specific facts from the context when possible."

    # Research a query: assemble context → ask SME → return Record.
    # @param query [String] natural language question
    # @param node_id [String, nil] optional starting node for graph traversal
    # @param max_tokens [Integer] limit response length (default 256)
    # @return [ContextRecord::Record] with answer in payload
    def research(query, node_id: nil, max_tokens: 512)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      context = assemble_context(query, node_id)
      user_message = build_user_message(query, context[:context])

      answer = @sme.chat(@system_prompt, user_message, max_tokens: max_tokens)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      build_result(query, answer, context, elapsed_sec: elapsed)
    end

    # Streaming research — yields tokens as they arrive.
    # @param query [String]
    # @param node_id [String, nil]
    # @param max_tokens [Integer]
    # @yield [String] each content chunk
    # @return [ContextRecord::Record] with answer + TTFS/total timings
    def research_stream(query, node_id: nil, max_tokens: 512, &block)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      context = assemble_context(query, node_id)
      retrieval_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
      user_message = build_user_message(query, context[:context])

      stream_result = @sme.chat_stream(
        @system_prompt, user_message,
        max_tokens: max_tokens, &block
      )

      total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      # Use content if available, fall back to reasoning for thinking-only models
      answer = stream_result[:content].empty? ? stream_result[:reasoning] : stream_result[:content]

      build_result(query, answer, context,
                   elapsed_sec: total,
                   ttfs: stream_result[:ttfs],
                   ttfs_content: stream_result[:ttfs_content],
                   retrieval_sec: retrieval_time,
                   tokens: stream_result[:tokens])
    end

    # Ingest a discovery back into the knowledge graph.
    # @param finding [Hash] content to ingest
    # @param source_id [String] identifier for the finding
    # @return [ContextRecord::Record, nil] ingest result or nil if no pipeline
    def ingest_finding(finding, source_id:)
      return nil unless @pipeline
      @pipeline.ingest(
        content: finding,
        source_id: source_id,
        metadata: { "origin" => "research_agent", "agent" => self.class.name }
      )
    end

    # Check if LLM servers are available.
    # @return [Hash] {conductor: bool, sme: bool}
    def server_status
      {
        conductor: @conductor.online?,
        sme: @sme.online?
      }
    end

    private

    def assemble_context(query, node_id)
      @assembler.assemble(node_id: node_id, query_text: query, top_k: 10)
    end

    def build_user_message(query, context_text)
      if context_text && !context_text.empty?
        "#{context_text}\n\n[QUESTION]\n#{query}"
      else
        query
      end
    end

    def build_result(query, answer, context, elapsed_sec:, ttfs: nil, ttfs_content: nil, retrieval_sec: nil, tokens: nil)
      meta = {
        "agent" => self.class.name,
        "sme" => @sme.name,
        "elapsed_sec" => elapsed_sec.round(3)
      }
      meta["ttfs"] = ttfs.round(3) if ttfs
      meta["ttfs_content"] = ttfs_content.round(3) if ttfs_content
      meta["retrieval_sec"] = retrieval_sec.round(3) if retrieval_sec
      meta["tokens"] = tokens if tokens

      Record.new(
        action: :execute,
        target: "research",
        rdf_type: "vv:ResearchEvent",
        payload: {
          "query" => query,
          "answer" => answer,
          "context_length" => context[:context].length,
          "sources" => context[:sources]
        },
        metadata: meta
      )
    end
  end
end

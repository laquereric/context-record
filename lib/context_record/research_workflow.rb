# frozen_string_literal: true

require "smith"
require "digest"

module ContextRecord
  # Smith workflow for the research pipeline:
  #   route → retrieve → answer → evaluate → ingest → done
  #
  # Uses deterministic steps backed by existing infrastructure.
  #
  # Usage:
  #   result = ResearchWorkflow.research(
  #     query: "What lens fits the Canon R5?",
  #     graph_store: store,
  #     llm_client: client
  #   )
  #   result.outcome_payload[:answer]
  class ResearchWorkflow < Smith::Workflow
    initial_state :route
    state :retrieve
    state :answer
    state :evaluate
    state :ingest
    state :done
    state :failed

    max_transitions 10

    transition :classify, from: :route, to: :retrieve do
      run do |step|
        query = step.read_context(:query)
        graph = step.read_context(:graph_store)

        node_id = nil
        if graph
          nodes = graph.find_nodes rescue []
          nodes.each do |node|
            label = node["label"]&.downcase || ""
            if label.length > 3 && query.to_s.downcase.include?(label)
              node_id = node["id"]
              break
            end
          end
        end

        step.write_context(:node_id, node_id)
      end
    end

    transition :assemble, from: :retrieve, to: :answer do
      run do |step|
        query = step.read_context(:query)
        node_id = step.read_context(:node_id)
        graph = step.read_context(:graph_store)
        vector = step.read_context(:vector_store)

        assembler = ContextRecord::ContextAssembler.new(graph_store: graph, vector_store: vector)
        context = assembler.assemble(node_id: node_id, query_text: query, top_k: 10)

        step.write_context(:assembled_context, context[:context])
        step.write_context(:sources, context[:sources])
      end
    end

    transition :generate, from: :answer, to: :evaluate do
      run do |step|
        query = step.read_context(:query)
        context_text = step.read_context(:assembled_context)
        client = step.read_context(:llm_client)
        system_prompt = step.read_context(:system_prompt) ||
          "You are a knowledgeable research assistant. Answer using the provided context. Cite specific facts."

        user_message = if context_text && !context_text.to_s.empty?
                         "#{context_text}\n\n[QUESTION]\n#{query}"
                       else
                         query.to_s
                       end

        answer = client.chat(system_prompt, user_message)
        step.write_context(:answer, answer)
      end
    end

    transition :check, from: :evaluate, to: :ingest do
      compute do |step|
        answer = step.read_context(:answer)

        if answer.nil? || answer.to_s.strip.length < 10
          step.write_context(:quality, :rejected)
          step.route_to(:fail_workflow)
        else
          step.write_context(:quality, :accepted)
        end
      end
    end

    transition :store, from: :ingest, to: :done do
      run do |step|
        answer = step.read_context(:answer)
        query = step.read_context(:query)
        sources = step.read_context(:sources)

        step.write_outcome(kind: :research_complete, payload: {
          answer: answer,
          sources: sources,
          quality: step.read_context(:quality)
        })
      end
    end

    transition :fail_workflow, from: :evaluate, to: :failed do
      compute do |step|
        step.write_outcome(kind: :research_failed, payload: {
          reason: "Quality check failed",
          answer: step.read_context(:answer)
        })
      end
    end

    # Convenience runner
    def self.research(query:, graph_store:, llm_client:, vector_store: nil,
                      pipeline: nil, system_prompt: nil)
      wf = new(context: {
        query: query,
        graph_store: graph_store,
        vector_store: vector_store,
        llm_client: llm_client,
        pipeline: pipeline,
        system_prompt: system_prompt
      })
      wf.run!
    end
  end
end

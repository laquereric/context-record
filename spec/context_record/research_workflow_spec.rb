# frozen_string_literal: true

require "spec_helper"
require "context_record/llm_client"
require "context_record/research_workflow"

# Mock LLM client for workflow testing
class WorkflowMockLlm
  attr_reader :name, :url, :last_system_prompt, :last_user_message

  def initialize(response: "Test answer from workflow.")
    @response = response
    @name = "mock"
    @url = "http://mock:0"
  end

  def chat(system_prompt, user_message, **_opts)
    @last_system_prompt = system_prompt
    @last_user_message = user_message
    @response
  end

  def online?
    true
  end
end

RSpec.describe ContextRecord::ResearchWorkflow do
  let(:graph_store) { ContextRecord::GraphStore.new }
  let(:mock_llm) { WorkflowMockLlm.new(response: "The SM7B uses XLR and works with the Scarlett 2i2.") }

  before do
    graph_store.add_node(id: "shure-sm7b", type: "bandh:Product", label: "Shure SM7B",
                         properties: { "connector" => "XLR" })
    graph_store.add_node(id: "scarlett-2i2", type: "bandh:Product", label: "Focusrite Scarlett 2i2",
                         properties: { "inputs" => "XLR" })
    graph_store.add_edge(source_id: "shure-sm7b", target_id: "scarlett-2i2",
                         rel_type: "vv:isCompatibleWith", properties: { "notes" => "XLR connection" })
  end

  describe ".research" do
    it "runs the full pipeline and returns a RunResult" do
      result = described_class.research(
        query: "What works with the Shure SM7B?",
        graph_store: graph_store,
        llm_client: mock_llm
      )

      expect(result).to be_a(Smith::Workflow::RunResult)
      expect(result.done?).to be true
    end

    it "produces an answer in the outcome" do
      result = described_class.research(
        query: "What works with the Shure SM7B?",
        graph_store: graph_store,
        llm_client: mock_llm
      )

      expect(result.outcome_kind).to eq(:research_complete)
      expect(result.outcome_payload[:answer]).to include("SM7B")
    end

    it "includes sources when graph context is found" do
      result = described_class.research(
        query: "What works with the Shure SM7B?",
        graph_store: graph_store,
        llm_client: mock_llm
      )

      expect(result.outcome_payload[:sources]).not_to be_empty
    end

    it "finds graph context and includes it in the answer" do
      result = described_class.research(
        query: "What works with the Shure SM7B?",
        graph_store: graph_store,
        llm_client: mock_llm
      )

      # The answer should come from the LLM (our mock)
      expect(result.outcome_payload[:answer]).to include("SM7B")
      # Sources should include the graph node
      expect(result.outcome_payload[:sources]).not_to be_empty
    end

    it "records steps" do
      result = described_class.research(
        query: "Test query",
        graph_store: graph_store,
        llm_client: mock_llm
      )

      transitions = result.steps.map { |s| s[:transition] }
      expect(transitions).to include(:classify, :assemble, :generate, :check, :store)
    end

    it "fails gracefully when LLM returns empty" do
      empty_llm = WorkflowMockLlm.new(response: "")
      result = described_class.research(
        query: "Test",
        graph_store: graph_store,
        llm_client: empty_llm
      )

      expect(result.outcome_kind).to eq(:research_failed)
    end

    it "accepts a custom system prompt and still produces a result" do
      result = described_class.research(
        query: "Test",
        graph_store: graph_store,
        llm_client: mock_llm,
        system_prompt: "You are a camera expert."
      )

      expect(result.done?).to be true
      expect(result.outcome_payload[:answer]).not_to be_nil
    end
  end
end

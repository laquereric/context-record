# frozen_string_literal: true

require "spec_helper"
require "context_record/llm_client"
require "context_record/research_agent"

# Mock LLM client for testing
class MockLlmClient
  attr_reader :name, :url, :last_system_prompt, :last_user_message

  def initialize(response: "This is a test answer.")
    @response = response
    @name = "mock"
    @url = "http://mock:0"
  end

  def chat(system_prompt, user_message, **_opts)
    @last_system_prompt = system_prompt
    @last_user_message = user_message
    @response
  end

  def conversation(messages, **_opts)
    @response
  end

  def online?
    true
  end
end

RSpec.describe ContextRecord::ResearchAgent do
  let(:graph_store) { ContextRecord::GraphStore.new }
  let(:mock_sme) { MockLlmClient.new(response: "The Canon R5 uses RF mount lenses.") }
  let(:mock_conductor) { MockLlmClient.new(response: '{"category":"cameras"}') }
  let(:agent) do
    described_class.new(
      graph_store: graph_store,
      conductor: mock_conductor,
      sme: mock_sme,
      system_prompt: "You are a camera expert."
    )
  end

  before do
    graph_store.add_node(id: "canon-r5", type: "bandh:Product", label: "Canon EOS R5", properties: { "mount" => "RF" })
    graph_store.add_node(id: "rf-24-105", type: "bandh:Product", label: "RF 24-105mm f/4L", properties: { "mount" => "RF" })
    graph_store.add_edge(source_id: "canon-r5", target_id: "rf-24-105", rel_type: "vv:isCompatibleWith", properties: { "notes" => "Same RF mount" })
  end

  describe "#research" do
    it "returns a Record with the answer" do
      result = agent.research("What lens fits the Canon R5?")
      expect(result).to be_a(ContextRecord::Record)
      expect(result.action).to eq(:execute)
      expect(result.rdf_type).to eq("vv:ResearchEvent")
      expect(result.payload["answer"]).to eq("The Canon R5 uses RF mount lenses.")
    end

    it "includes the query in the payload" do
      result = agent.research("What lens fits the Canon R5?")
      expect(result.payload["query"]).to eq("What lens fits the Canon R5?")
    end

    it "includes timing metadata" do
      result = agent.research("test query")
      expect(result.metadata["elapsed_sec"]).to be_a(Float)
      expect(result.metadata["sme"]).to eq("mock")
    end

    it "passes context to the SME" do
      agent.research("What lens fits the Canon R5?", node_id: "canon-r5")
      # The mock captures what was sent
      expect(mock_sme.last_user_message).to include("Canon EOS R5")
      expect(mock_sme.last_user_message).to include("What lens fits the Canon R5?")
    end

    it "uses the custom system prompt" do
      agent.research("test")
      expect(mock_sme.last_system_prompt).to eq("You are a camera expert.")
    end
  end

  describe "#server_status" do
    it "reports server availability" do
      status = agent.server_status
      expect(status[:conductor]).to be true
      expect(status[:sme]).to be true
    end
  end

  describe "#ingest_finding" do
    it "returns nil when no pipeline configured" do
      result = agent.ingest_finding({ "type" => "discovery" }, source_id: "test")
      expect(result).to be_nil
    end
  end
end

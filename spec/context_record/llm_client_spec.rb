# frozen_string_literal: true

require "spec_helper"
require "context_record/llm_client"

RSpec.describe ContextRecord::LlmClient do
  describe "#initialize" do
    it "accepts url and name" do
      client = described_class.new(url: "http://localhost:8081", name: "test")
      expect(client.url).to eq("http://localhost:8081")
      expect(client.name).to eq("test")
    end

    it "defaults name to url" do
      client = described_class.new(url: "http://localhost:8081")
      expect(client.name).to eq("http://localhost:8081")
    end
  end

  describe ".from_env" do
    it "creates conductor client on port 8080" do
      client = described_class.from_env(role: :conductor)
      expect(client.url).to eq("http://localhost:8080")
      expect(client.name).to eq("conductor")
    end

    it "creates sme client on port 8081" do
      client = described_class.from_env(role: :sme)
      expect(client.url).to eq("http://localhost:8081")
      expect(client.name).to eq("sme")
    end
  end

  describe "#online?" do
    it "returns false when server is not running" do
      client = described_class.new(url: "http://localhost:19999")
      expect(client.online?).to be false
    end
  end
end

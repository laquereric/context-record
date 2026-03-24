# frozen_string_literal: true

RSpec.describe ContextRecord::Record do
  let(:record) { described_class.new(action: :read, target: "users") }

  describe "#initialize" do
    it "sets a UUID id" do
      expect(record.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "sets action as symbol" do
      expect(record.action).to eq(:read)
    end

    it "sets target as string" do
      expect(record.target).to eq("users")
    end

    it "defaults payload to frozen empty hash" do
      expect(record.payload).to eq({})
      expect(record.payload).to be_frozen
    end

    it "defaults context to VV_CONTEXT" do
      expect(record.context).to eq(described_class::VV_CONTEXT)
    end

    it "sets timestamp to utc Time" do
      expect(record.timestamp).to be_a(Time)
      expect(record.timestamp.utc?).to be true
    end

    it "raises on invalid action" do
      expect { described_class.new(action: :explode, target: "x") }
        .to raise_error(ArgumentError, /Invalid action/)
    end

    it "deep-freezes payload" do
      r = described_class.new(action: :read, target: "x", payload: { key: "val" })
      expect(r.payload).to be_frozen
      expect(r.payload[:key]).to be_frozen
    end

    it "is frozen after initialization" do
      expect(record).to be_frozen
    end

    it "accepts all valid actions" do
      described_class::VALID_ACTIONS.each do |action|
        expect { described_class.new(action: action, target: "x") }.not_to raise_error
      end
    end

    it "accepts :evaluate action" do
      expect { described_class.new(action: :evaluate, target: "x") }.not_to raise_error
    end
  end

  describe "#to_json_ld" do
    it "returns a Hash with sorted keys" do
      result = record.to_json_ld
      expect(result.keys).to eq(result.keys.sort)
    end

    it "includes @context" do
      expect(record.to_json_ld["@context"]).to eq(described_class::VV_CONTEXT)
    end

    it "expands ContextPrimitive values in payload" do
      primitive = ContextRecord::ContextPrimitive.new(type: "vv:Action", value: "filter")
      r = described_class.new(action: :read, target: "users", payload: { filter: primitive })
      expanded = r.to_json_ld["payload"]
      expect(expanded[:filter]).to eq({ "@type" => "vv:Action", "@value" => "filter" })
    end

    it "is deterministic for identical payloads" do
      payload = { name: "Alice", role: "admin" }
      r1 = described_class.new(action: :read, target: "users", payload: payload)
      r2 = described_class.new(action: :read, target: "users", payload: payload)
      # IDs differ (UUID), but everything else must be identical
      ld1 = r1.to_json_ld.reject { |k, _| k == "id" || k == "timestamp" }
      ld2 = r2.to_json_ld.reject { |k, _| k == "id" || k == "timestamp" }
      expect(ld1).to eq(ld2)
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      parsed = JSON.parse(record.to_json)
      expect(parsed["target"]).to eq("users")
      expect(parsed["action"]).to eq("read")
    end
  end

  describe "#json_ld?" do
    it "returns false for default VV_CONTEXT" do
      expect(record.json_ld?).to be false
    end

    it "returns true for custom context" do
      r = described_class.new(action: :read, target: "x", context: "https://schema.org/")
      expect(r.json_ld?).to be true
    end
  end
end

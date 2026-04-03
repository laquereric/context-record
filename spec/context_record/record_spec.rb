# frozen_string_literal: true

RSpec.describe ContextRecord::Record do
  let(:record) { described_class.new(action: :read, target: "users") }

  describe "#initialize" do
    it "sets a UUID id" do
      expect(record.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "sets iri as urn:vv:record:<uuid>" do
      expect(record.iri).to eq("urn:vv:record:#{record.id}")
    end

    it "defaults rdf_type to vv:Event" do
      expect(record.rdf_type).to eq("vv:Event")
    end

    it "accepts custom rdf_type" do
      r = described_class.new(action: :read, target: "x", rdf_type: "bandh:ProductQuery")
      expect(r.rdf_type).to eq("bandh:ProductQuery")
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

  describe "#to_h" do
    it "does NOT include @id (backward compatible)" do
      expect(record.to_h).not_to have_key("@id")
    end

    it "does NOT include @type (backward compatible)" do
      expect(record.to_h).not_to have_key("@type")
    end

    it "includes id as plain UUID" do
      expect(record.to_h["id"]).to eq(record.id)
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

    it "includes @id as IRI" do
      expect(record.to_json_ld["@id"]).to eq("urn:vv:record:#{record.id}")
    end

    it "includes @type defaulting to vv:Event" do
      expect(record.to_json_ld["@type"]).to eq("vv:Event")
    end

    it "includes custom @type when rdf_type is set" do
      r = described_class.new(action: :read, target: "x", rdf_type: "iadbot:Reflection")
      expect(r.to_json_ld["@type"]).to eq("iadbot:Reflection")
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
      skip_keys = %w[@id id timestamp]
      ld1 = r1.to_json_ld.reject { |k, _| skip_keys.include?(k) }
      ld2 = r2.to_json_ld.reject { |k, _| skip_keys.include?(k) }
      expect(ld1).to eq(ld2)
    end
  end

  describe "#to_json" do
    it "returns valid JSON" do
      parsed = JSON.parse(record.to_json)
      expect(parsed["target"]).to eq("users")
      expect(parsed["action"]).to eq("read")
    end

    it "includes @id and @type in JSON output" do
      parsed = JSON.parse(record.to_json)
      expect(parsed["@id"]).to start_with("urn:vv:record:")
      expect(parsed["@type"]).to eq("vv:Event")
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

  describe "#linked_records" do
    it "returns empty array when no links in metadata" do
      expect(record.linked_records).to eq([])
    end

    it "extracts IRI from string value" do
      r = described_class.new(
        action: :create, target: "x",
        metadata: { "vv:causedBy" => "urn:vv:record:abc-123" }
      )
      expect(r.linked_records).to eq(["urn:vv:record:abc-123"])
    end

    it "extracts IRIs from array values" do
      r = described_class.new(
        action: :create, target: "x",
        metadata: { "vv:relatedTo" => ["urn:vv:record:aaa", "urn:vv:record:bbb"] }
      )
      expect(r.linked_records).to contain_exactly("urn:vv:record:aaa", "urn:vv:record:bbb")
    end

    it "ignores non-IRI strings" do
      r = described_class.new(
        action: :create, target: "x",
        metadata: { "note" => "not a link", "vv:causedBy" => "urn:vv:record:abc" }
      )
      expect(r.linked_records).to eq(["urn:vv:record:abc"])
    end

    it "extracts IRIs from nested hashes" do
      r = described_class.new(
        action: :create, target: "x",
        metadata: { "nested" => { "deep" => "urn:vv:record:deep-one" } }
      )
      expect(r.linked_records).to eq(["urn:vv:record:deep-one"])
    end
  end
end

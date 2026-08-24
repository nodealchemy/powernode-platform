# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::SharedKnowledgeTool do
  let(:account) { create(:account) }
  # Behaviour examples, constructed as an in-process system caller. The
  # per-action gate (G4) requires that opt-in to be EXPLICIT — a nil user does
  # not imply internal. Authorization is pinned in
  # read_gated_tools_action_permission_spec.rb.
  let(:tool) { described_class.new(account: account, internal: true) }

  describe ".action_definitions" do
    it "exposes a tags filter parameter on search_knowledge" do
      params = described_class.action_definitions["search_knowledge"][:parameters]

      expect(params).to have_key(:tags)
      expect(params[:tags][:type]).to eq("array")
    end
  end

  describe "#execute action: search_knowledge" do
    # Both entries match the "widget" keyword search so, absent tag filtering,
    # both come back — the tags param is what must narrow this to one.
    # embedding left nil so the search falls back to the deterministic keyword
    # path instead of vector similarity (avoids flakiness / provider setup).
    let!(:alpha_entry) do
      create(:ai_shared_knowledge, account: account, title: "Alpha Widget Doc",
             content: "Widget assembly instructions for the alpha line.",
             tags: [ "alpha" ], embedding: nil)
    end

    let!(:beta_entry) do
      create(:ai_shared_knowledge, account: account, title: "Beta Widget Doc",
             content: "Widget assembly instructions for the beta line.",
             tags: [ "beta" ], embedding: nil)
    end

    it "filters results by the tags parameter" do
      result = tool.execute(params: { action: "search_knowledge", query: "widget", tags: [ "alpha" ] })

      expect(result[:success]).to be true
      titles = result[:entries].map { |e| e[:title] }
      expect(titles).to include("Alpha Widget Doc")
      expect(titles).not_to include("Beta Widget Doc")
    end

    it "returns all matching entries when tags is omitted" do
      result = tool.execute(params: { action: "search_knowledge", query: "widget" })

      expect(result[:success]).to be true
      titles = result[:entries].map { |e| e[:title] }
      expect(titles).to include("Alpha Widget Doc", "Beta Widget Doc")
    end
  end

  # Found in production 2026-08-02: the tags filter worked in-process but was
  # inert over MCP. The value arrives as a JSON *string* rather than an Array,
  # so `Array(params[:tags])` wrapped the literal text `["alpha"]` as ONE tag
  # and matched nothing. The same coercion feeds create/update, where it does
  # not merely miss — it PERSISTS the bogus single tag.
  describe "tags arriving as a JSON string (MCP transport)" do
    let!(:alpha) do
      Ai::Memory::SharedKnowledgeService.new(account: account).create(
        title: "Alpha Widget Doc", content: "widget alpha content",
        content_type: "text", access_level: "team", tags: %w[alpha]
      )
    end
    let!(:beta) do
      Ai::Memory::SharedKnowledgeService.new(account: account).create(
        title: "Beta Widget Doc", content: "widget beta content",
        content_type: "text", access_level: "team", tags: %w[beta]
      )
    end

    before do
      allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
    end

    it "parses a JSON-encoded tags string when filtering" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: '["alpha"]'
      })

      expect(result[:success]).to be true
      expect(result[:entries].map { |e| e[:title] }).to eq(["Alpha Widget Doc"])
    end

    it "stores parsed tags on create rather than the raw JSON string" do
      result = tool.execute(params: {
        action: "create_knowledge", title: "Gamma Doc",
        content: "gamma content for tag coercion", content_type: "text",
        access_level: "team", tags: '["gamma","delta"]'
      })

      expect(result[:success]).to be true
      stored = Ai::SharedKnowledge.find(result[:entry][:id]).tags
      expect(stored).to contain_exactly("gamma", "delta")
    end

    it "still accepts a real array unchanged" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: ["beta"]
      })

      expect(result[:entries].map { |e| e[:title] }).to eq(["Beta Widget Doc"])
    end

    it "treats a bare non-JSON string as a single tag" do
      result = tool.execute(params: {
        action: "search_knowledge", query: "widget", tags: "alpha"
      })

      expect(result[:entries].map { |e| e[:title] }).to eq(["Alpha Widget Doc"])
    end
  end
end

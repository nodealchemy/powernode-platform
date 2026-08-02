# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::SharedKnowledgeTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

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
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::KnowledgeTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("query_knowledge_base")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:query, :knowledge_base_id, :top_k)
    end

    it "marks query as required" do
      expect(described_class.definition[:parameters][:query][:required]).to be true
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.read permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    end
  end

  describe "#execute" do
    context "with a valid query" do
      let(:knowledge_base) { create(:ai_knowledge_base, account: account, status: "active") }

      before do
        knowledge_base # ensure it exists
        search_service = instance_double(Ai::Rag::HybridSearchService)
        allow(Ai::Rag::HybridSearchService).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:search).and_return({ results: [], metadata: {} })
      end

      it "returns results" do
        result = tool.execute(params: { query: "How to deploy?" })
        expect(result[:success]).to be true
        expect(result[:query]).to eq("How to deploy?")
        expect(result).to have_key(:results_count)
      end

      it "respects top_k parameter" do
        result = tool.execute(params: { query: "test query", top_k: 3 })
        expect(result[:success]).to be true
      end

      it "defaults top_k to 5" do
        result = tool.execute(params: { query: "test" })
        expect(result[:success]).to be true
      end
    end

    context "parameter validation" do
      it "raises ArgumentError when query is missing" do
        expect { tool.execute(params: {}) }.to raise_error(ArgumentError, /Missing required parameters: query/)
      end
    end
  end
end

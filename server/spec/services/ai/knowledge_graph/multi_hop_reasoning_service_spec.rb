# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraph::MultiHopReasoningService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  describe "#reason" do
    context "with no nodes in graph" do
      it "returns empty result" do
        result = service.reason(query: "What is Ruby?")

        expect(result[:answer_nodes]).to be_empty
        expect(result[:paths]).to be_empty
        expect(result[:confidence]).to eq(0.0)
        expect(result[:seed_nodes_found]).to eq(0)
      end
    end

    context "with nodes in graph" do
      let!(:ruby_node) do
        create(:ai_knowledge_graph_node,
               account: account,
               name: "Ruby",
               node_type: "entity",
               entity_type: "technology",
               description: "A dynamic programming language")
      end

      let!(:rails_node) do
        create(:ai_knowledge_graph_node,
               account: account,
               name: "Rails",
               node_type: "entity",
               entity_type: "technology",
               description: "A web application framework for Ruby")
      end

      let!(:edge) do
        create(:ai_knowledge_graph_edge,
               account: account,
               source_node: rails_node,
               target_node: ruby_node,
               relation_type: "depends_on")
      end

      it "finds relevant nodes and paths" do
        result = service.reason(query: "Ruby programming language")

        expect(result[:query]).to eq("Ruby programming language")
        expect(result).to have_key(:answer_nodes)
        expect(result).to have_key(:paths)
        expect(result).to have_key(:reasoning_chain)
        expect(result).to have_key(:confidence)
      end

      it "respects max_hops parameter" do
        result = service.reason(query: "Ruby", max_hops: 1)
        expect(result).to have_key(:paths)
      end

      it "respects top_k parameter" do
        result = service.reason(query: "Ruby", top_k: 1)
        expect(result[:paths].size).to be <= 1
      end
    end
  end
end

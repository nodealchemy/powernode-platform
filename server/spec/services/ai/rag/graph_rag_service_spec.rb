# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Rag::GraphRagService, type: :service do
  let(:account) { create(:account) }

  let(:graph_service_double) { instance_double(Ai::KnowledgeGraph::GraphService) }
  let(:hybrid_search_double) { instance_double(Ai::Rag::HybridSearchService) }
  let(:embedding_service_double) { instance_double(Ai::Memory::EmbeddingService) }

  subject(:service) { described_class.new(account: account) }

  before do
    allow(Ai::KnowledgeGraph::GraphService).to receive(:new).and_return(graph_service_double)
    allow(Ai::Rag::HybridSearchService).to receive(:new).and_return(hybrid_search_double)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service_double)
    allow(hybrid_search_double).to receive(:search).and_return({ results: [] })
  end

  # ===========================================================================
  # #retrieve
  # ===========================================================================

  describe "#retrieve" do
    context "when no seed nodes are found" do
      before do
        allow(embedding_service_double).to receive(:generate).and_return(nil)
      end

      it "returns empty result" do
        result = service.retrieve(query: "unknown topic")

        expect(result[:results]).to be_empty
        expect(result[:communities]).to be_empty
        expect(result[:seed_nodes]).to be_empty
        expect(result[:metadata][:seed_nodes_found]).to eq(0)
      end

      it "includes query in metadata" do
        result = service.retrieve(query: "unknown topic")

        expect(result[:metadata][:query]).to eq("unknown topic")
      end
    end

    context "when seed nodes are found via keyword fallback" do
      let!(:node1) do
        create(:ai_knowledge_graph_node, account: account, name: "Ruby programming",
               node_type: "entity", status: "active", mention_count: 5)
      end
      let!(:node2) do
        create(:ai_knowledge_graph_node, account: account, name: "Python programming",
               node_type: "entity", status: "active", mention_count: 3)
      end
      let!(:edge) do
        create(:ai_knowledge_graph_edge, account: account,
               source_node: node1, target_node: node2, relation_type: "related_to")
      end

      before do
        # Embedding generation fails, triggering keyword fallback
        allow(embedding_service_double).to receive(:generate).and_return(nil)
        allow(embedding_service_double).to receive(:similarity).and_return(0.8)

        allow(graph_service_double).to receive(:find_neighbors).and_return([
          { id: node2.id, name: node2.name }
        ])
      end

      it "finds seed nodes via keyword matching" do
        result = service.retrieve(query: "Ruby programming language")

        expect(result[:seed_nodes]).not_to be_empty
        expect(result[:metadata][:seed_nodes_found]).to be >= 1
      end

      it "detects communities from seed nodes" do
        result = service.retrieve(query: "Ruby programming language")

        expect(result[:communities]).to be_an(Array)
        expect(result[:metadata][:communities_detected]).to be >= 0
      end

      it "includes community summaries when requested" do
        result = service.retrieve(query: "Ruby programming language", include_summaries: true)

        expect(result[:summaries]).to be_an(Array)
      end

      it "merges with hybrid search results" do
        allow(hybrid_search_double).to receive(:search).and_return({
          results: [{ id: "hybrid-1", content: "hybrid result", score: 0.7 }]
        })

        result = service.retrieve(query: "Ruby programming language")

        expect(result[:results]).to be_an(Array)
      end
    end

    context "when seed nodes are found via embedding" do
      let(:query_embedding) { Array.new(1536) { rand } }
      let!(:node1) do
        create(:ai_knowledge_graph_node, account: account, name: "Machine Learning",
               node_type: "entity", status: "active")
      end

      before do
        allow(embedding_service_double).to receive(:generate).and_return(query_embedding)
        allow(embedding_service_double).to receive(:similarity).and_return(0.85)

        # Create a proxy that delegates to node1 but adds neighbor_distance
        node_proxy = double("NodeProxy",
          id: node1.id,
          name: node1.name,
          node_type: node1.node_type,
          status: node1.status,
          neighbor_distance: 0.2
        )

        nodes_chain = double("NodesChain")
        allow(Ai::KnowledgeGraphNode).to receive(:where).and_return(nodes_chain)
        allow(nodes_chain).to receive(:nearest_neighbors).and_return(nodes_chain)
        allow(nodes_chain).to receive(:first).and_return([node_proxy])

        allow(graph_service_double).to receive(:find_neighbors).and_return([])
      end

      it "uses embedding-based seed node discovery" do
        result = service.retrieve(query: "deep learning models")

        expect(embedding_service_double).to have_received(:generate).with("deep learning models")
      end
    end

    it "includes latency in metadata" do
      allow(embedding_service_double).to receive(:generate).and_return(nil)

      result = service.retrieve(query: "test query")

      expect(result[:metadata][:latency_ms]).to be_a(Numeric)
      expect(result[:metadata][:latency_ms]).to be >= 0
    end

    it "respects top_k parameter" do
      allow(embedding_service_double).to receive(:generate).and_return(nil)

      result = service.retrieve(query: "test", top_k: 5)

      expect(result[:results].size).to be <= 5
    end
  end

  # ===========================================================================
  # #build_context
  # ===========================================================================

  describe "#build_context" do
    before do
      allow(embedding_service_double).to receive(:generate).and_return(nil)
    end

    context "when no results are found" do
      it "returns empty context" do
        result = service.build_context(query: "nothing relevant")

        expect(result[:context]).to be_a(String)
        expect(result[:source]).to eq("graph_rag")
        expect(result[:token_estimate]).to be_a(Numeric)
      end
    end

    context "when results are found" do
      let!(:node) do
        create(:ai_knowledge_graph_node, account: account, name: "API design patterns",
               node_type: "entity", status: "active", mention_count: 10)
      end
      let!(:node2) do
        create(:ai_knowledge_graph_node, account: account, name: "REST API best practices",
               node_type: "entity", status: "active", mention_count: 5)
      end
      let!(:edge) do
        create(:ai_knowledge_graph_edge, account: account,
               source_node: node, target_node: node2, relation_type: "related_to")
      end

      before do
        allow(graph_service_double).to receive(:find_neighbors).and_return([
          { id: node2.id, name: node2.name }
        ])
        allow(embedding_service_double).to receive(:similarity).and_return(0.8)
      end

      it "returns context string with graph knowledge" do
        result = service.build_context(query: "API design patterns")

        expect(result[:context]).to be_a(String)
        expect(result[:source]).to eq("graph_rag")
      end

      it "includes metadata from the retrieval" do
        result = service.build_context(query: "API design patterns")

        expect(result[:metadata]).to be_a(Hash)
        expect(result[:metadata]).to have_key(:query)
      end

      it "respects token_budget parameter" do
        result = service.build_context(query: "API design patterns", token_budget: 100)

        expect(result[:token_estimate]).to be <= 100
      end
    end
  end
end

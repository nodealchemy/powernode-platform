# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::KnowledgeGraph::GraphService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  describe "#create_node" do
    it "creates a node with required attributes" do
      node = service.create_node(name: "Ruby", node_type: "entity", entity_type: "technology")

      expect(node).to be_persisted
      expect(node.name).to eq("Ruby")
      expect(node.node_type).to eq("entity")
      expect(node.entity_type).to eq("technology")
      expect(node.account).to eq(account)
    end

    it "creates a concept node" do
      node = service.create_node(name: "Object-Oriented Programming", node_type: "concept")

      expect(node.node_type).to eq("concept")
    end

    it "raises error for invalid node_type" do
      expect {
        service.create_node(name: "Test", node_type: "invalid")
      }.to raise_error(Ai::KnowledgeGraph::GraphServiceError, /Invalid node_type/)
    end

    it "generates embedding when description provided" do
      node = service.create_node(
        name: "Ruby",
        node_type: "entity",
        description: "A programming language"
      )

      expect(node.embedding).to be_present
    end
  end

  describe "#update_node" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account, name: "Old Name") }

    it "updates node attributes" do
      updated = service.update_node(node.id, name: "New Name", description: "Updated desc")
      expect(updated.name).to eq("New Name")
      expect(updated.description).to eq("Updated desc")
    end
  end

  describe "#delete_node" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account) }

    it "deletes the node" do
      expect { service.delete_node(node.id) }.to change(Ai::KnowledgeGraphNode, :count).by(-1)
    end

    it "raises error for non-existent node" do
      expect {
        service.delete_node(SecureRandom.uuid)
      }.to raise_error(Ai::KnowledgeGraph::GraphServiceError, /Node not found/)
    end
  end

  describe "#list_nodes" do
    before do
      create(:ai_knowledge_graph_node, account: account, node_type: "entity", entity_type: "person", name: "Alice")
      create(:ai_knowledge_graph_node, :concept, account: account, name: "Machine Learning")
      create(:ai_knowledge_graph_node, :archived, account: account, name: "Old Node")
    end

    it "returns active nodes" do
      nodes = service.list_nodes
      expect(nodes.size).to eq(2)
    end

    it "filters by node_type" do
      nodes = service.list_nodes(node_type: "entity")
      expect(nodes.size).to eq(1)
      expect(nodes.first.name).to eq("Alice")
    end

    it "searches by query" do
      nodes = service.list_nodes(query: "Machine")
      expect(nodes.size).to eq(1)
      expect(nodes.first.name).to eq("Machine Learning")
    end
  end

  describe "#create_edge" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    it "creates an edge between two nodes" do
      edge = service.create_edge(source: node_a, target: node_b, relation_type: "related_to")

      expect(edge).to be_persisted
      expect(edge.source_node).to eq(node_a)
      expect(edge.target_node).to eq(node_b)
      expect(edge.relation_type).to eq("related_to")
    end

    it "accepts node IDs instead of node objects" do
      edge = service.create_edge(source: node_a.id, target: node_b.id, relation_type: "depends_on")
      expect(edge).to be_persisted
    end

    it "raises error for invalid relation type" do
      expect {
        service.create_edge(source: node_a, target: node_b, relation_type: "invalid")
      }.to raise_error(Ai::KnowledgeGraph::GraphServiceError, /Invalid relation_type/)
    end
  end

  describe "#find_neighbors" do
    let(:center) { create(:ai_knowledge_graph_node, account: account, name: "Center") }
    let(:neighbor1) { create(:ai_knowledge_graph_node, account: account, name: "Neighbor 1") }
    let(:neighbor2) { create(:ai_knowledge_graph_node, account: account, name: "Neighbor 2") }
    let(:distant) { create(:ai_knowledge_graph_node, account: account, name: "Distant") }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: center, target_node: neighbor1)
      create(:ai_knowledge_graph_edge, account: account, source_node: center, target_node: neighbor2,
                                       relation_type: "depends_on")
      create(:ai_knowledge_graph_edge, account: account, source_node: neighbor1, target_node: distant,
                                       relation_type: "is_a")
    end

    it "returns direct neighbors at depth 1" do
      result = service.find_neighbors(node: center, depth: 1)
      names = result.map { |r| r[:name] }
      expect(names).to include("Neighbor 1", "Neighbor 2")
      expect(names).not_to include("Distant")
    end

    it "returns multi-hop neighbors at depth 2" do
      result = service.find_neighbors(node: center, depth: 2)
      names = result.map { |r| r[:name] }
      expect(names).to include("Neighbor 1", "Neighbor 2", "Distant")
    end

    it "filters by relation types" do
      result = service.find_neighbors(node: center, depth: 1, relation_types: ["depends_on"])
      names = result.map { |r| r[:name] }
      expect(names).to include("Neighbor 2")
      expect(names).not_to include("Neighbor 1")
    end
  end

  describe "#shortest_path" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account, name: "A") }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account, name: "B") }
    let(:node_c) { create(:ai_knowledge_graph_node, account: account, name: "C") }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b)
      create(:ai_knowledge_graph_edge, account: account, source_node: node_b, target_node: node_c,
                                       relation_type: "depends_on")
    end

    it "finds path between connected nodes" do
      path = service.shortest_path(source: node_a, target: node_c)
      expect(path).not_to be_nil
      expect(path.size).to eq(2)
    end

    it "returns nil when no path exists" do
      isolated = create(:ai_knowledge_graph_node, account: account, name: "Isolated")
      path = service.shortest_path(source: node_a, target: isolated)
      expect(path).to be_nil
    end
  end

  describe "#subgraph" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b)
    end

    it "returns nodes and edges for given node_ids" do
      result = service.subgraph(node_ids: [node_a.id, node_b.id])

      expect(result[:nodes].size).to eq(2)
      expect(result[:edges].size).to eq(1)
    end

    it "can exclude edges" do
      result = service.subgraph(node_ids: [node_a.id], include_edges: false)
      expect(result[:nodes].size).to eq(1)
      expect(result).not_to have_key(:edges)
    end
  end

  describe "#merge_nodes" do
    let(:keep_node) { create(:ai_knowledge_graph_node, account: account, name: "Keep", mention_count: 5) }
    let(:merge_node) { create(:ai_knowledge_graph_node, account: account, name: "Merge", mention_count: 3) }
    let(:connected) { create(:ai_knowledge_graph_node, account: account, name: "Connected") }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: merge_node, target_node: connected,
                                       relation_type: "depends_on")
    end

    it "merges nodes and reassigns edges" do
      result = service.merge_nodes(keep: keep_node, merge: merge_node, reason: "duplicate")

      expect(result.id).to eq(keep_node.id)
      expect(result.mention_count).to eq(8)

      merge_node.reload
      expect(merge_node.status).to eq("merged")
      expect(merge_node.merged_into_id).to eq(keep_node.id)

      # Edge should be reassigned
      edge = Ai::KnowledgeGraphEdge.active.find_by(source_node_id: keep_node.id, target_node_id: connected.id)
      expect(edge).to be_present
    end
  end

  describe "#statistics" do
    before do
      n1 = create(:ai_knowledge_graph_node, account: account, node_type: "entity")
      n2 = create(:ai_knowledge_graph_node, account: account, node_type: "entity")
      n3 = create(:ai_knowledge_graph_node, :concept, account: account)
      create(:ai_knowledge_graph_edge, account: account, source_node: n1, target_node: n2)
      create(:ai_knowledge_graph_edge, account: account, source_node: n2, target_node: n3,
                                       relation_type: "is_a")
    end

    it "returns graph statistics" do
      stats = service.statistics

      expect(stats[:node_count]).to eq(3)
      expect(stats[:edge_count]).to eq(2)
      expect(stats[:by_node_type]).to include("entity" => 2, "concept" => 1)
      expect(stats[:by_relation_type]).to include("related_to" => 1, "is_a" => 1)
      expect(stats[:avg_degree]).to be > 0
    end
  end
end

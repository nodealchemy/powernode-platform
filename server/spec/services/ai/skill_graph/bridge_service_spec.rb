# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::BridgeService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  # Prevent after_commit callback from auto-creating KG nodes
  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#sync_skill" do
    let(:skill) { create(:ai_skill, account: account, name: "Code Review", description: "Automated code review", category: "productivity", tags: ["code", "review"]) }

    it "creates a KG node linked to the skill" do
      node = service.sync_skill(skill)

      expect(node).to be_persisted
      expect(node.name).to eq("Code Review")
      expect(node.entity_type).to eq("skill")
      expect(node.node_type).to eq("entity")
      expect(node.ai_skill_id).to eq(skill.id)
      expect(node.account).to eq(account)
      expect(node.status).to eq("active")
      expect(node.confidence).to eq(1.0)
    end

    it "generates an embedding for the node" do
      node = service.sync_skill(skill)
      expect(node.embedding).to be_present
    end

    it "stores skill properties on the node" do
      node = service.sync_skill(skill)
      expect(node.properties["category"]).to eq("productivity")
      expect(node.properties["tags"]).to eq(["code", "review"])
    end

    it "updates an existing KG node on re-sync" do
      first_node = service.sync_skill(skill)
      skill.update!(name: "Advanced Code Review")
      second_node = service.sync_skill(skill.reload)

      expect(second_node.id).to eq(first_node.id)
      expect(second_node.name).to eq("Advanced Code Review")
    end

    it "returns nil and logs on failure" do
      allow_any_instance_of(Ai::KnowledgeGraph::GraphService).to receive(:create_node).and_raise(StandardError, "DB error")
      expect(Rails.logger).to receive(:error).with(/sync_skill failed/)
      expect(service.sync_skill(skill)).to be_nil
    end
  end

  describe "#sync_all_skills" do
    before do
      create(:ai_skill, account: account, name: "Skill A", category: "productivity", status: "active")
      create(:ai_skill, account: account, name: "Skill B", category: "sales", status: "active")
      create(:ai_skill, account: account, name: "Skill C", category: "finance", status: "inactive")
    end

    it "syncs only active account skills" do
      result = service.sync_all_skills
      expect(result[:synced]).to eq(2)
      expect(result[:failed]).to eq(0)
    end
  end

  describe "#create_skill_edge" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "productivity") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
    end

    it "creates an edge between two skill nodes" do
      edge = service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "requires"
      )

      expect(edge).to be_persisted
      expect(edge.relation_type).to eq("requires")
      expect(edge.source_node_id).to eq(skill_a.reload.knowledge_graph_node.id)
      expect(edge.target_node_id).to eq(skill_b.reload.knowledge_graph_node.id)
    end

    it "raises ArgumentError for invalid relation type" do
      expect {
        service.create_skill_edge(
          source_skill_id: skill_a.id,
          target_skill_id: skill_b.id,
          relation_type: "invalid_type"
        )
      }.to raise_error(ArgumentError, /Invalid skill relation_type/)
    end

    it "raises error when skill node not found" do
      expect {
        service.create_skill_edge(
          source_skill_id: SecureRandom.uuid,
          target_skill_id: skill_b.id,
          relation_type: "requires"
        )
      }.to raise_error(Ai::KnowledgeGraph::GraphServiceError, /Skill node not found/)
    end
  end

  describe "#remove_skill_edge" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "sales") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
    end

    it "deletes the edge" do
      edge = service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "enhances"
      )

      expect { service.remove_skill_edge(edge.id) }.to change(Ai::KnowledgeGraphEdge, :count).by(-1)
    end
  end

  describe "#skill_subgraph" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "sales") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
      service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "requires"
      )
    end

    it "returns all skill nodes and interconnecting edges" do
      result = service.skill_subgraph

      expect(result[:node_count]).to eq(2)
      expect(result[:edge_count]).to eq(1)
      expect(result[:nodes].map { |n| n[:name] }).to contain_exactly("Skill A", "Skill B")
      expect(result[:edges].first[:relation_type]).to eq("requires")
    end
  end

  describe "#auto_detect_relationships" do
    let(:skill) { create(:ai_skill, account: account, name: "Target Skill", category: "productivity") }

    it "returns empty when skill has no KG node" do
      result = service.auto_detect_relationships(skill)
      expect(result).to eq([])
    end
  end
end

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

  # IMP-059e6c5af2bf — global skills (account_id nil) never trigger the model
  # sync hook, so per-account node copies come only from this bridge (seed
  # post-sync / sync_all_skills). Each account must get its OWN node copy: the
  # unscoped has_one :knowledge_graph_node returns an arbitrary account's node
  # for a global skill, so an unscoped lookup here made account B's sync
  # UPDATE account A's node instead of creating B's copy.
  describe "global skills across accounts" do
    let(:other_account) { create(:account) }
    let(:global_skill) do
      create(:ai_skill, account: nil, name: "Design Skill From Intent",
             description: "Author a skill from intent", category: "skill_management")
    end

    it "gives each account its own node copy without clobbering the other's" do
      node_a = service.sync_skill(global_skill)
      # Fresh model object, as every real request has — the shared-object form
      # false-passes through the has_one's cached nil from before A's insert.
      node_b = described_class.new(other_account).sync_skill(Ai::Skill.find(global_skill.id))

      expect(node_a.reload.account_id).to eq(account.id)
      expect(node_b.account_id).to eq(other_account.id)
      expect(node_b.id).not_to eq(node_a.id)
      expect(Ai::KnowledgeGraphNode.where(ai_skill_id: global_skill.id).count).to eq(2)
    end

    it "archives and detaches every account's node copy when the skill is destroyed" do
      node_ids = [
        service.sync_skill(global_skill).id,
        described_class.new(other_account).sync_skill(Ai::Skill.find(global_skill.id)).id
      ]

      # Pre-fix this raised PG::ForeignKeyViolation outright: the has_one's
      # dependent: :nullify cleared only one copy's FK, so a global skill with
      # synced copies could not be destroyed at all.
      Ai::Skill.find(global_skill.id).destroy!

      nodes = Ai::KnowledgeGraphNode.where(id: node_ids)
      expect(nodes.pluck(:status)).to all(eq("archived"))
      expect(nodes.pluck(:ai_skill_id)).to all(be_nil)
    end

    it "covers global skills in sync_all_skills" do
      global_skill
      results = service.sync_all_skills

      expect(results[:synced]).to be >= 1
      expect(Ai::KnowledgeGraphNode.find_by(ai_skill_id: global_skill.id, account_id: account.id)).to be_present
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::ConflictDetectionService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#scan_all" do
    it "returns a summary with all conflict types" do
      result = service.scan_all

      expect(result).to have_key(:conflicts)
      expect(result).to have_key(:summary)
      expect(result).to have_key(:total)
      expect(result).to have_key(:scanned_at)
      expect(result[:conflicts]).to have_key(:duplicate)
      expect(result[:conflicts]).to have_key(:overlapping)
      expect(result[:conflicts]).to have_key(:circular_dependency)
      expect(result[:conflicts]).to have_key(:stale)
      expect(result[:conflicts]).to have_key(:orphan)
      expect(result[:conflicts]).to have_key(:version_drift)
    end

    it "returns zero totals for an empty graph" do
      result = service.scan_all

      expect(result[:total]).to eq(0)
    end
  end

  describe "#detect_stale_skills" do
    it "detects skills that are old, unused, and low-usage" do
      stale_skill = create(:ai_skill, account: account,
        created_at: 60.days.ago,
        usage_count: 2,
        last_used_at: 100.days.ago
      )

      result = service.detect_stale_skills

      expect(result.size).to eq(1)
      conflict = result.first
      expect(conflict.conflict_type).to eq("stale")
      expect(conflict.severity).to eq("low")
      expect(conflict.auto_resolvable).to be true
      expect(conflict.skill_a_id).to eq(stale_skill.id)
    end

    it "does not flag recently created skills" do
      create(:ai_skill, account: account,
        created_at: 10.days.ago,
        usage_count: 0,
        last_used_at: nil
      )

      result = service.detect_stale_skills

      expect(result).to be_empty
    end

    it "does not flag skills with sufficient usage" do
      create(:ai_skill, account: account,
        created_at: 60.days.ago,
        usage_count: 10,
        last_used_at: 100.days.ago
      )

      result = service.detect_stale_skills

      expect(result).to be_empty
    end

    it "is idempotent - does not create duplicate conflicts" do
      create(:ai_skill, account: account,
        created_at: 60.days.ago,
        usage_count: 1,
        last_used_at: nil
      )

      first_run = service.detect_stale_skills
      second_run = service.detect_stale_skills

      expect(first_run.size).to eq(1)
      expect(second_run).to be_empty
    end
  end

  describe "#detect_orphan_skills" do
    it "detects skills without agent assignments or KG edges" do
      orphan_skill = create(:ai_skill, account: account, created_at: 45.days.ago)

      result = service.detect_orphan_skills

      expect(result.size).to eq(1)
      conflict = result.first
      expect(conflict.conflict_type).to eq("orphan")
      expect(conflict.severity).to eq("low")
      expect(conflict.skill_a_id).to eq(orphan_skill.id)
    end

    it "does not flag skills with agent assignments" do
      skill = create(:ai_skill, account: account, created_at: 45.days.ago)
      agent = create(:ai_agent, account: account)
      create(:ai_agent_skill, agent: agent, skill: skill)

      result = service.detect_orphan_skills

      expect(result).to be_empty
    end

    it "does not flag recently created skills" do
      create(:ai_skill, account: account, created_at: 5.days.ago)

      result = service.detect_orphan_skills

      expect(result).to be_empty
    end

    it "does not flag skills with KG edges" do
      skill = create(:ai_skill, account: account, created_at: 45.days.ago)
      other_skill = create(:ai_skill, account: account, created_at: 45.days.ago)

      # Create KG nodes for both skills
      node = Ai::KnowledgeGraphNode.create!(
        account: account, name: skill.name, entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill.id
      )
      other_node = Ai::KnowledgeGraphNode.create!(
        account: account, name: other_skill.name, entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: other_skill.id
      )

      # Create edge connecting them
      Ai::KnowledgeGraphEdge.create!(
        account: account,
        source_node: node,
        target_node: other_node,
        relation_type: "requires",
        status: "active",
        weight: 0.8,
        confidence: 0.9
      )

      result = service.detect_orphan_skills

      orphan_ids = result.map(&:skill_a_id)
      expect(orphan_ids).not_to include(skill.id)
    end
  end

  describe "#detect_version_drift" do
    it "detects skills sharing the same name prefix" do
      create(:ai_skill, account: account, name: "Deploy v1")
      create(:ai_skill, account: account, name: "Deploy v2")

      result = service.detect_version_drift

      expect(result.size).to eq(1)
      conflict = result.first
      expect(conflict.conflict_type).to eq("version_drift")
      expect(conflict.severity).to eq("medium")
      expect(conflict.auto_resolvable).to be false
    end

    it "does not flag skills with different prefixes" do
      create(:ai_skill, account: account, name: "Code review")
      create(:ai_skill, account: account, name: "Data analysis")

      result = service.detect_version_drift

      expect(result).to be_empty
    end

    it "creates pairwise conflicts for groups of 3+" do
      create(:ai_skill, account: account, name: "Deploy alpha")
      create(:ai_skill, account: account, name: "Deploy beta")
      create(:ai_skill, account: account, name: "Deploy gamma")

      result = service.detect_version_drift

      # 3 choose 2 = 3 pairs
      expect(result.size).to eq(3)
    end

    it "is idempotent" do
      create(:ai_skill, account: account, name: "Test v1")
      create(:ai_skill, account: account, name: "Test v2")

      first_run = service.detect_version_drift
      second_run = service.detect_version_drift

      expect(first_run.size).to eq(1)
      expect(second_run).to be_empty
    end
  end

  describe "#detect_duplicates" do
    it "returns empty when no skill nodes with embeddings exist" do
      result = service.detect_duplicates
      expect(result).to be_empty
    end

    it "detects skills with very high similarity" do
      skill_a = create(:ai_skill, account: account, name: "Code Review A")
      skill_b = create(:ai_skill, account: account, name: "Code Review B")

      # Create nodes with identical embeddings — pgvector will return distance ≈ 0 (similarity ≈ 1.0)
      Ai::KnowledgeGraphNode.create!(
        account: account, name: "Code Review A", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_a.id, embedding: Array.new(1536, 0.1)
      )
      Ai::KnowledgeGraphNode.create!(
        account: account, name: "Code Review B", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_b.id, embedding: Array.new(1536, 0.1)
      )

      result = service.detect_duplicates

      expect(result.size).to be >= 1
      expect(result.first.conflict_type).to eq("duplicate")
      expect(result.first.severity).to eq("critical")
    end
  end

  describe "#detect_overlapping" do
    it "returns empty when no skill nodes exist" do
      result = service.detect_overlapping
      expect(result).to be_empty
    end
  end

  describe "#detect_circular_dependencies" do
    it "returns empty when no edges create cycles" do
      result = service.detect_circular_dependencies
      expect(result).to be_empty
    end
  end
end

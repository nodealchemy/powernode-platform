# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::AutoRepairService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#auto_resolve_all" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_conflict_auto_resolve, account).and_return(false)
      end

      it "returns skipped result" do
        result = service.auto_resolve_all

        expect(result[:resolved]).to eq(0)
        expect(result[:failed]).to eq(0)
        expect(result[:skipped]).to eq("feature_flag_disabled")
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_conflict_auto_resolve, account).and_return(true)
      end

      it "processes auto-resolvable conflicts" do
        skill = create(:ai_skill, account: account, effectiveness_score: 0.5)
        create(:ai_skill_conflict, :stale, :auto_resolvable,
          account: account,
          skill_a: skill,
          status: "detected"
        )

        result = service.auto_resolve_all

        expect(result[:resolved]).to eq(1)
        expect(result[:failed]).to eq(0)
      end

      it "returns zero counts when no conflicts exist" do
        result = service.auto_resolve_all

        expect(result[:resolved]).to eq(0)
        expect(result[:failed]).to eq(0)
      end
    end
  end

  describe "#resolve_conflict" do
    describe "duplicate resolution" do
      let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", usage_count: 10) }
      let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", usage_count: 3) }
      let(:conflict) do
        create(:ai_skill_conflict, :overlapping,
          account: account,
          skill_a: skill_a,
          skill_b: skill_b,
          conflict_type: "duplicate",
          severity: "critical",
          auto_resolvable: true,
          status: "detected",
          resolution_strategy: "merge_to_higher_usage"
        )
      end

      let(:mock_graph_service) { instance_double(Ai::KnowledgeGraph::GraphService) }

      before do
        allow(Ai::KnowledgeGraph::GraphService).to receive(:new).and_return(mock_graph_service)
        allow(mock_graph_service).to receive(:merge_nodes)
      end

      it "keeps the higher-usage skill and archives the lower-usage skill" do
        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:winner_id]).to eq(skill_a.id)
        expect(result[:loser_id]).to eq(skill_b.id)

        skill_b.reload
        expect(skill_b.status).to eq("inactive")
        expect(skill_b.is_enabled).to be false
      end

      it "reassigns agent_skills from loser to winner" do
        agent = create(:ai_agent, account: account)
        create(:ai_agent_skill, agent: agent, skill: skill_b)

        service.resolve_conflict(conflict)

        expect(Ai::AgentSkill.where(ai_skill_id: skill_b.id).count).to eq(0)
        expect(Ai::AgentSkill.where(ai_agent_id: agent.id, ai_skill_id: skill_a.id).count).to eq(1)
      end

      it "does not duplicate agent_skills if winner already has the assignment" do
        agent = create(:ai_agent, account: account)
        create(:ai_agent_skill, agent: agent, skill: skill_a)
        create(:ai_agent_skill, agent: agent, skill: skill_b)

        service.resolve_conflict(conflict)

        expect(Ai::AgentSkill.where(ai_agent_id: agent.id, ai_skill_id: skill_a.id).count).to eq(1)
        expect(Ai::AgentSkill.where(ai_skill_id: skill_b.id).count).to eq(0)
      end
    end

    describe "stale resolution" do
      let(:skill) { create(:ai_skill, account: account, effectiveness_score: 0.5) }
      let(:conflict) do
        create(:ai_skill_conflict, :stale,
          account: account,
          skill_a: skill,
          status: "detected",
          auto_resolvable: true
        )
      end

      it "decays effectiveness score by 0.1" do
        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("effectiveness_decayed")
        expect(result[:new]).to eq(0.4)

        skill.reload
        expect(skill.effectiveness_score).to eq(0.4)
      end

      it "returns already_low_effectiveness when below 0.2" do
        skill.update_column(:effectiveness_score, 0.05)

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("already_low_effectiveness")
      end

      it "auto-resolves skills already below 0.2 threshold" do
        skill.update_column(:effectiveness_score, 0.1)

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("already_low_effectiveness")
      end
    end

    describe "orphan resolution" do
      let(:skill) { create(:ai_skill, account: account, created_at: 70.days.ago) }
      let(:conflict) do
        create(:ai_skill_conflict, :orphan,
          account: account,
          skill_a: skill,
          status: "detected",
          auto_resolvable: true
        )
      end

      let(:mock_bridge) { instance_double(Ai::SkillGraph::BridgeService) }

      before do
        allow(Ai::SkillGraph::BridgeService).to receive(:new).and_return(mock_bridge)
      end

      it "creates edges when relationships are detected" do
        other_skill = create(:ai_skill, account: account)
        allow(mock_bridge).to receive(:auto_detect_relationships).and_return([
          { skill_id: other_skill.id, suggested_relation: "composes", similarity: 0.7, confidence: 0.8 }
        ])
        allow(mock_bridge).to receive(:create_skill_edge)

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("relationships_created")
        expect(result[:count]).to eq(1)
      end

      it "creates improvement recommendation when no relationships found and skill is old" do
        allow(mock_bridge).to receive(:auto_detect_relationships).and_return([])

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("recommendation_created")

        recommendation = Ai::ImprovementRecommendation.last
        expect(recommendation.recommendation_type).to eq("skill_consolidation")
        expect(recommendation.target_id).to eq(skill.id)
        expect(recommendation.evidence["title"]).to include("orphan")
      end

      it "defers resolution for young skills with no relationships" do
        skill.update_column(:created_at, 35.days.ago)
        allow(mock_bridge).to receive(:auto_detect_relationships).and_return([])

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("deferred_too_young")
      end
    end

    describe "overlapping resolution" do
      let(:skill_a) { create(:ai_skill, account: account, name: "Skill Alpha", category: "productivity") }
      let(:skill_b) { create(:ai_skill, account: account, name: "Skill Beta", category: "productivity") }
      let(:conflict) do
        create(:ai_skill_conflict, :overlapping,
          account: account,
          skill_a: skill_a,
          skill_b: skill_b,
          status: "detected",
          similarity_score: 0.8
        )
      end

      it "creates an improvement recommendation" do
        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("recommendation_created")

        recommendation = Ai::ImprovementRecommendation.last
        expect(recommendation.recommendation_type).to eq("skill_consolidation")
        expect(recommendation.evidence["title"]).to include("overlapping")
      end
    end

    describe "circular dependency resolution" do
      let(:skill_a) { create(:ai_skill, account: account) }
      let(:skill_b) { create(:ai_skill, account: account) }

      it "archives the specified edge" do
        node_a = Ai::KnowledgeGraphNode.create!(
          account: account, name: "A", entity_type: "skill",
          node_type: "entity", status: "active", confidence: 1.0,
          ai_skill_id: skill_a.id
        )
        node_b = Ai::KnowledgeGraphNode.create!(
          account: account, name: "B", entity_type: "skill",
          node_type: "entity", status: "active", confidence: 1.0,
          ai_skill_id: skill_b.id
        )
        edge = Ai::KnowledgeGraphEdge.create!(
          account: account, source_node: node_a, target_node: node_b,
          relation_type: "requires", status: "active", weight: 0.5, confidence: 0.5
        )

        conflict = create(:ai_skill_conflict, :circular_dependency,
          account: account,
          skill_a: skill_a,
          skill_b: skill_b,
          status: "detected",
          auto_resolvable: true,
          edge_id: edge.id
        )

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("edge_archived")
        expect(edge.reload.status).to eq("archived")
      end
    end

    describe "version drift resolution" do
      let(:skill_a) { create(:ai_skill, account: account, name: "Deploy v1") }
      let(:skill_b) { create(:ai_skill, account: account, name: "Deploy v2") }
      let(:conflict) do
        create(:ai_skill_conflict, :version_drift,
          account: account,
          skill_a: skill_a,
          skill_b: skill_b,
          status: "detected",
          resolution_details: {
            "skill_a_name" => "Deploy v1",
            "skill_b_name" => "Deploy v2",
            "shared_prefix" => "Deploy"
          }
        )
      end

      it "creates an improvement recommendation" do
        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be true
        expect(result[:action]).to eq("recommendation_created")

        recommendation = Ai::ImprovementRecommendation.last
        expect(recommendation.recommendation_type).to eq("skill_consolidation")
        expect(recommendation.evidence["title"]).to include("version drift")
      end
    end

    describe "unknown conflict type" do
      it "returns failure for unknown types" do
        skill = create(:ai_skill, account: account)
        conflict = create(:ai_skill_conflict,
          account: account,
          skill_a: skill,
          conflict_type: "duplicate",
          severity: "low",
          status: "detected"
        )
        # Manually set an invalid type to bypass validation
        conflict.update_column(:conflict_type, "unknown_type")

        result = service.resolve_conflict(conflict)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Unknown conflict type")
      end
    end
  end
end

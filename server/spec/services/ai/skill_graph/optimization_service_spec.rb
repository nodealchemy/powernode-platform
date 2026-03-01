# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::OptimizationService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  # Shared stubs for all sub-services
  let(:mock_conflict_detection) { instance_double(Ai::SkillGraph::ConflictDetectionService) }
  let(:mock_auto_repair) { instance_double(Ai::SkillGraph::AutoRepairService) }
  let(:mock_evolution) { instance_double(Ai::SkillGraph::EvolutionService) }
  let(:mock_self_learning) { instance_double(Ai::SkillGraph::SelfLearningService) }
  let(:mock_health_score) { instance_double(Ai::SkillGraph::HealthScoreService) }
  let(:mock_bridge) { instance_double(Ai::SkillGraph::BridgeService) }
  let(:mock_graph) { instance_double(Ai::KnowledgeGraph::GraphService) }

  before do
    allow(Ai::SkillGraph::ConflictDetectionService).to receive(:new).and_return(mock_conflict_detection)
    allow(Ai::SkillGraph::AutoRepairService).to receive(:new).and_return(mock_auto_repair)
    allow(Ai::SkillGraph::EvolutionService).to receive(:new).and_return(mock_evolution)
    allow(Ai::SkillGraph::SelfLearningService).to receive(:new).and_return(mock_self_learning)
    allow(Ai::SkillGraph::HealthScoreService).to receive(:new).and_return(mock_health_score)
    allow(Ai::SkillGraph::BridgeService).to receive(:new).and_return(mock_bridge)
    allow(Ai::KnowledgeGraph::GraphService).to receive(:new).and_return(mock_graph)
  end

  describe "#daily_maintenance" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(false)
      end

      it "returns skipped result" do
        result = service.daily_maintenance

        expect(result[:skipped]).to be true
        expect(result[:reason]).to include("feature flag disabled")
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(true)
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_conflict_auto_resolve, account).and_return(true)
        allow(mock_conflict_detection).to receive(:scan_all).and_return({ total: 3 })
        allow(mock_auto_repair).to receive(:auto_resolve_all).and_return({ resolved: 2, failed: 1 })
        allow(mock_evolution).to receive(:decay_stale_skills).and_return(5)
        allow(mock_graph).to receive(:statistics).and_return({ total_nodes: 50 })
      end

      it "runs conflict scan" do
        expect(mock_conflict_detection).to receive(:scan_all)

        service.daily_maintenance
      end

      it "runs auto-resolve when its flag is enabled" do
        expect(mock_auto_repair).to receive(:auto_resolve_all)

        service.daily_maintenance
      end

      it "skips auto-resolve when its flag is disabled" do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_conflict_auto_resolve, account).and_return(false)

        expect(mock_auto_repair).not_to receive(:auto_resolve_all)

        service.daily_maintenance
      end

      it "decays stale skills" do
        expect(mock_evolution).to receive(:decay_stale_skills)

        service.daily_maintenance
      end

      it "refreshes KG statistics" do
        expect(mock_graph).to receive(:statistics)

        service.daily_maintenance
      end

      it "returns results summary" do
        result = service.daily_maintenance

        expect(result[:conflicts_found]).to be_present
        expect(result[:auto_resolved]).to be_present
        expect(result[:skills_decayed]).to eq(5)
        expect(result[:stats]).to be_present
        expect(result[:ran_at]).to be_present
      end
    end
  end

  describe "#weekly_maintenance" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(false)
      end

      it "returns skipped result" do
        result = service.weekly_maintenance

        expect(result[:skipped]).to be true
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(true)
        allow(mock_self_learning).to receive(:propose_prompt_refinements).and_return(["skill-1", "skill-2"])
        allow(mock_self_learning).to receive(:detect_capability_gaps).and_return({ gaps: [], proposed_categories: [] })
        allow(mock_self_learning).to receive(:recalculate_all_effectiveness).and_return(10)
        allow(mock_health_score).to receive(:calculate).and_return({ score: 75.0, grade: "C", components: {} })
      end

      it "proposes prompt refinements" do
        expect(mock_self_learning).to receive(:propose_prompt_refinements)

        service.weekly_maintenance
      end

      it "detects capability gaps" do
        expect(mock_self_learning).to receive(:detect_capability_gaps)

        service.weekly_maintenance
      end

      it "recalculates effectiveness scores" do
        expect(mock_self_learning).to receive(:recalculate_all_effectiveness)

        service.weekly_maintenance
      end

      it "snapshots health score" do
        expect(mock_health_score).to receive(:calculate)

        service.weekly_maintenance
      end

      it "returns results summary" do
        result = service.weekly_maintenance

        expect(result[:refinements_proposed]).to eq(2)
        expect(result[:gaps_detected]).to be_a(Hash)
        expect(result[:effectiveness_updated]).to eq(10)
        expect(result[:health_score][:score]).to eq(75.0)
        expect(result[:ran_at]).to be_present
      end
    end
  end

  describe "#monthly_maintenance" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(false)
      end

      it "returns skipped result" do
        result = service.monthly_maintenance

        expect(result[:skipped]).to be true
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(true)
        allow(mock_bridge).to receive(:sync_all_skills).and_return({ synced: 15, failed: 0 })
        allow(mock_health_score).to receive(:comprehensive_report).and_return({ health: { score: 80 } })
      end

      it "re-embeds all skills" do
        expect(mock_bridge).to receive(:sync_all_skills)

        service.monthly_maintenance
      end

      it "generates comprehensive health report" do
        expect(mock_health_score).to receive(:comprehensive_report)

        service.monthly_maintenance
      end

      it "archives old resolved conflicts" do
        skill = create(:ai_skill, account: account)
        # Old resolved conflict - should be archived
        create(:ai_skill_conflict, :resolved,
          account: account,
          skill_a: skill,
          resolved_at: 100.days.ago
        )
        # Recent resolved conflict - should not be archived
        create(:ai_skill_conflict, :resolved,
          account: account,
          skill_a: skill,
          resolved_at: 10.days.ago
        )

        result = service.monthly_maintenance

        expect(result[:conflicts_archived]).to eq(1)
      end

      it "returns results summary" do
        result = service.monthly_maintenance

        expect(result[:skills_reembedded][:synced]).to eq(15)
        expect(result[:health_report]).to be_present
        expect(result[:ran_at]).to be_present
      end
    end
  end

  describe "#on_demand" do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(true)
    end

    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_optimization, account).and_return(false)
      end

      it "returns skipped result for any operation" do
        result = service.on_demand(operation: :full)

        expect(result[:skipped]).to be true
      end
    end

    describe ":scan_conflicts operation" do
      it "runs conflict detection" do
        allow(mock_conflict_detection).to receive(:scan_all).and_return({ total: 5 })

        result = service.on_demand(operation: :scan_conflicts)

        expect(result[:conflicts_found][:total]).to eq(5)
      end
    end

    describe ":auto_resolve operation" do
      it "runs auto-repair" do
        allow(mock_auto_repair).to receive(:auto_resolve_all).and_return({ resolved: 3, failed: 0 })

        result = service.on_demand(operation: :auto_resolve)

        expect(result[:auto_resolved][:resolved]).to eq(3)
      end
    end

    describe ":decay operation" do
      it "decays stale skills" do
        allow(mock_evolution).to receive(:decay_stale_skills).and_return(4)

        result = service.on_demand(operation: :decay)

        expect(result[:skills_decayed]).to eq(4)
      end
    end

    describe ":health operation" do
      it "calculates health score" do
        allow(mock_health_score).to receive(:calculate).and_return({ score: 85.0, grade: "B" })

        result = service.on_demand(operation: :health)

        expect(result[:health][:score]).to eq(85.0)
      end
    end

    describe ":effectiveness operation" do
      it "recalculates effectiveness" do
        allow(mock_self_learning).to receive(:recalculate_all_effectiveness).and_return(8)

        result = service.on_demand(operation: :effectiveness)

        expect(result[:effectiveness_updated]).to eq(8)
      end
    end

    describe ":reembed operation" do
      it "re-embeds all skills" do
        allow(mock_bridge).to receive(:sync_all_skills).and_return({ synced: 12, failed: 0 })

        result = service.on_demand(operation: :reembed)

        expect(result[:skills_reembedded][:synced]).to eq(12)
      end
    end

    describe ":full operation" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_conflict_auto_resolve, account).and_return(true)
        allow(mock_conflict_detection).to receive(:scan_all).and_return({ total: 2 })
        allow(mock_auto_repair).to receive(:auto_resolve_all).and_return({ resolved: 1, failed: 0 })
        allow(mock_evolution).to receive(:decay_stale_skills).and_return(3)
        allow(mock_graph).to receive(:statistics).and_return({})
        allow(mock_self_learning).to receive(:propose_prompt_refinements).and_return([])
        allow(mock_self_learning).to receive(:detect_capability_gaps).and_return({ gaps: [] })
        allow(mock_self_learning).to receive(:recalculate_all_effectiveness).and_return(5)
        allow(mock_health_score).to receive(:calculate).and_return({ score: 70.0 })
      end

      it "runs both daily and weekly maintenance" do
        result = service.on_demand(operation: :full)

        expect(result).to have_key(:daily)
        expect(result).to have_key(:weekly)
      end
    end

    describe "unknown operation" do
      it "returns error for unknown operation" do
        result = service.on_demand(operation: :nonexistent)

        expect(result[:error]).to include("Unknown operation")
      end
    end
  end
end

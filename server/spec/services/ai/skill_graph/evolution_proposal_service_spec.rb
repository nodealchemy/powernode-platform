# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::EvolutionProposalService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#run" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_scheduled_evolution, account).and_return(false)
      end

      it "returns a skipped result and files no recommendations" do
        create(:ai_skill, account: account, effectiveness_score: 0.1,
                          positive_usage_count: 2, negative_usage_count: 10)
        create(:ai_skill_conflict, account: account)

        expect {
          result = service.run
          expect(result[:skipped]).to be true
        }.not_to change(Ai::ImprovementRecommendation, :count)
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_scheduled_evolution, account).and_return(true)
      end

      describe "low-effectiveness skill evolution proposals" do
        it "drafts an evolved version and files a pending skill_health recommendation" do
          skill = create(:ai_skill, account: account, name: "Weak Skill", effectiveness_score: 0.2,
                                     positive_usage_count: 3, negative_usage_count: 8, last_used_at: Time.current)

          result = service.run

          expect(result[:evolution_proposals]).to eq(1)
          rec = Ai::ImprovementRecommendation.where(recommendation_type: "skill_health").last
          expect(rec.status).to eq("pending")
          expect(rec.target_type).to eq("Ai::Skill")
          expect(rec.target_id).to eq(skill.id)

          version_id = rec.recommended_config["proposed_version_id"]
          expect(version_id).to be_present
          version = Ai::SkillVersion.find(version_id)
          expect(version.ai_skill_id).to eq(skill.id)
          expect(version.is_active).to be false
        end

        it "never mutates the skill itself — proposal only" do
          skill = create(:ai_skill, account: account, effectiveness_score: 0.2,
                                     positive_usage_count: 3, negative_usage_count: 8)

          expect { service.run }.not_to change { skill.reload.attributes.except("updated_at") }
        end

        it "skips skills under the usage sample floor" do
          create(:ai_skill, account: account, effectiveness_score: 0.1,
                            positive_usage_count: 1, negative_usage_count: 2)

          result = service.run
          expect(result[:evolution_proposals]).to eq(0)
        end

        it "skips skills at or above the effectiveness threshold" do
          create(:ai_skill, account: account, effectiveness_score: 0.6,
                            positive_usage_count: 8, negative_usage_count: 2)

          result = service.run
          expect(result[:evolution_proposals]).to eq(0)
        end

        it "does not re-propose while a recommendation is already pending (idempotent per cycle)" do
          create(:ai_skill, account: account, effectiveness_score: 0.2,
                            positive_usage_count: 3, negative_usage_count: 8)

          service.run
          expect { service.run }.not_to change(Ai::ImprovementRecommendation, :count)
        end

        it "clone-on-evolves a global skill instead of drafting onto the shared baseline (F5)" do
          global_skill = create(:ai_skill, :global, :system_skill, name: "Global Baseline",
                                slug: "global-baseline-#{SecureRandom.hex(3)}", category: "productivity",
                                effectiveness_score: 0.15, positive_usage_count: 4, negative_usage_count: 8)

          result = service.run

          expect(result[:evolution_proposals]).to eq(1)
          rec = Ai::ImprovementRecommendation.where(recommendation_type: "skill_health").last
          expect(rec.target_id).not_to eq(global_skill.id)

          target_skill = Ai::Skill.find(rec.target_id)
          expect(target_skill.account_id).to eq(account.id)
          expect(target_skill.cloned_from_id).to eq(global_skill.id)

          # The global baseline itself is never versioned or touched.
          expect(global_skill.reload.versions.count).to eq(0)
          expect(global_skill.effectiveness_score).to eq(0.15)
        end
      end

      describe "conflict review proposals" do
        it "files a pending skill_consolidation recommendation for an active conflict" do
          conflict = create(:ai_skill_conflict, :overlapping, account: account)

          result = service.run

          expect(result[:conflict_review_proposals]).to eq(1)
          rec = Ai::ImprovementRecommendation.where(recommendation_type: "skill_consolidation").last
          expect(rec.status).to eq("pending")
          expect(rec.target_type).to eq("Ai::SkillConflict")
          expect(rec.target_id).to eq(conflict.id)
        end

        it "never resolves or dismisses the conflict itself — proposal only" do
          conflict = create(:ai_skill_conflict, :stale, account: account)

          service.run

          expect(conflict.reload.status).to eq("detected")
        end

        it "skips conflicts that are already resolved or dismissed" do
          create(:ai_skill_conflict, :resolved, account: account)
          create(:ai_skill_conflict, :dismissed, account: account)

          result = service.run
          expect(result[:conflict_review_proposals]).to eq(0)
        end

        it "does not re-propose while a recommendation is already pending for the same conflict" do
          create(:ai_skill_conflict, :version_drift, account: account)

          service.run
          expect { service.run }.not_to change(Ai::ImprovementRecommendation, :count)
        end

        it "covers every conflict type, not just the auto_resolvable ones" do
          create(:ai_skill_conflict, :overlapping, account: account) # auto_resolvable: false
          create(:ai_skill_conflict, :stale, :auto_resolvable, account: account)

          result = service.run
          expect(result[:conflict_review_proposals]).to eq(2)
        end
      end
    end
  end
end

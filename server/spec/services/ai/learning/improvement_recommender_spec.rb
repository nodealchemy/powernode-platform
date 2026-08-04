# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::ImprovementRecommender, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#generate_recommendations" do
    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:trajectory_analysis).and_return(false)
      end

      it "returns empty array" do
        expect(service.generate_recommendations).to eq([])
      end
    end

    context "when feature flag is enabled" do
      let(:analyzer) { instance_double(Ai::Learning::TrajectoryAnalyzer) }

      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:trajectory_analysis).and_return(true)
        allow(Ai::Learning::TrajectoryAnalyzer).to receive(:new).and_return(analyzer)
      end

      context "with no analyses" do
        before do
          allow(analyzer).to receive(:analyze).and_return([])
        end

        it "returns empty array" do
          expect(service.generate_recommendations).to eq([])
        end
      end

      context "with analyses" do
        let(:agent) { create(:ai_agent, account: account) }
        let(:analysis) do
          {
            recommendation_type: "provider_switch",
            target_type: "Ai::Agent",
            target_id: agent.id,
            current_config: { provider_id: "old", success_rate: 60.0 },
            recommended_config: { provider_id: "new", success_rate: 90.0 },
            evidence: { improvement: "30% higher success rate" },
            confidence_score: 0.8
          }
        end

        before do
          allow(analyzer).to receive(:analyze).and_return([analysis])
        end

        it "creates ImprovementRecommendation records" do
          expect {
            service.generate_recommendations
          }.to change(Ai::ImprovementRecommendation, :count).by(1)
        end

        it "returns the created recommendations" do
          results = service.generate_recommendations
          expect(results.length).to eq(1)
          expect(results.first).to be_a(Ai::ImprovementRecommendation)
          expect(results.first.recommendation_type).to eq("provider_switch")
        end

        it "updates existing pending recommendation instead of duplicating" do
          service.generate_recommendations

          updated_analysis = analysis.merge(confidence_score: 0.9)
          allow(analyzer).to receive(:analyze).and_return([updated_analysis])

          expect {
            service.generate_recommendations
          }.not_to change(Ai::ImprovementRecommendation, :count)

          recommendation = Ai::ImprovementRecommendation.last
          expect(recommendation.confidence_score).to eq(0.9)
        end
      end

      context "when recommendation creation fails" do
        before do
          allow(analyzer).to receive(:analyze).and_return([{
            recommendation_type: nil,
            target_type: nil,
            target_id: nil
          }])
        end

        it "returns nil for failed creations" do
          results = service.generate_recommendations
          expect(results.compact).to be_empty
        end
      end

      context "with an agent_reliability analysis (previously a phantom type)" do
        let(:agent) { create(:ai_agent, account: account) }

        before do
          allow(analyzer).to receive(:analyze).and_return([{
            recommendation_type: "agent_reliability",
            target_type: "Ai::Agent",
            target_id: agent.id,
            current_config: { failure_rate: 40.0 },
            recommended_config: {},
            evidence: { suggestion: "review" },
            confidence_score: 0.7
          }])
        end

        it "now persists the recommendation instead of silently dropping it" do
          expect { service.generate_recommendations }
            .to change(Ai::ImprovementRecommendation, :count).by(1)
          expect(Ai::ImprovementRecommendation.last.recommendation_type).to eq("agent_reliability")
        end
      end

      # Policy tuning (Api::V1::Internal::Ai::AutonomyController#analyze_policy_patterns)
      # writes agent_reliability rows against the same (account, Ai::Agent, agent)
      # tuple this analyzer produces. Its rows are tagged with evidence["source"];
      # updating one here would replace the whole evidence column and destroy the
      # title/description/priority the observation sensor reads.
      context "when another writer owns a pending row for the same tuple" do
        let(:agent) { create(:ai_agent, account: account) }
        let!(:policy_row) do
          create(:ai_improvement_recommendation, :pending,
                 account: account,
                 recommendation_type: "agent_reliability",
                 target_type: "Ai::Agent",
                 target_id: agent.id,
                 confidence_score: 0.8333,
                 evidence: {
                   "title" => "Only 16.7% approval rate",
                   "description" => "Based on 12 proposals",
                   "priority" => "high",
                   "suggestion_type" => "quality_concern",
                   "source" => "policy_tuning"
                 })
        end

        before do
          allow(analyzer).to receive(:analyze).and_return([{
            recommendation_type: "agent_reliability",
            target_type: "Ai::Agent",
            target_id: agent.id,
            current_config: { agent_name: agent.name, failure_rate: 40.0 },
            recommended_config: {},
            evidence: { suggestion: "Review configuration or provider." },
            confidence_score: 0.4
          }])
        end

        it "leaves the other writer's evidence intact" do
          service.generate_recommendations

          evidence = policy_row.reload.evidence
          expect(evidence["title"]).to eq("Only 16.7% approval rate")
          expect(evidence["description"]).to eq("Based on 12 proposals")
          expect(evidence["priority"]).to eq("high")
          expect(evidence["suggestion_type"]).to eq("quality_concern")
        end

        it "leaves the other writer's confidence score intact" do
          service.generate_recommendations

          expect(policy_row.reload.confidence_score.to_f).to be_within(0.0001).of(0.8333)
        end

        it "writes its own row instead of hijacking that one" do
          expect { service.generate_recommendations }
            .to change(Ai::ImprovementRecommendation, :count).by(1)

          own = Ai::ImprovementRecommendation.where(recommendation_type: "agent_reliability").order(:created_at).last
          expect(own.id).not_to eq(policy_row.id)
          expect(own.evidence["suggestion"]).to eq("Review configuration or provider.")
        end

        it "still dedupes against its own untagged row on a second run" do
          service.generate_recommendations

          expect { service.generate_recommendations }
            .not_to change(Ai::ImprovementRecommendation, :count)
        end
      end
    end

    context "when the account kill switch is active (gate #3)" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:trajectory_analysis).and_return(true)
        allow(account).to receive(:ai_suspended?).and_return(true)
      end

      it "writes no recommendations and skips analysis entirely" do
        expect(Ai::Learning::TrajectoryAnalyzer).not_to receive(:new)
        expect(service.generate_recommendations).to eq([])
      end
    end
  end

  describe "#apply_recommendation!" do
    let(:user) { create(:user, account: account) }
    let(:agent) { create(:ai_agent, account: account) }
    let(:new_provider) { create(:ai_provider, account: account) }

    context "with a provider_switch recommendation" do
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "provider_switch",
               target_type: "Ai::Agent",
               target_id: agent.id,
               recommended_config: { "provider_id" => new_provider.id })
      end

      it "switches the agent's provider" do
        service.apply_recommendation!(recommendation.id, user: user)

        agent.reload
        expect(agent.ai_provider_id).to eq(new_provider.id)
      end

      it "marks the recommendation as applied" do
        service.apply_recommendation!(recommendation.id, user: user)

        recommendation.reload
        expect(recommendation.status).to eq("applied")
      end

      it "returns the recommendation" do
        result = service.apply_recommendation!(recommendation.id, user: user)
        expect(result).to eq(recommendation)
      end
    end

    context "with a skill_health recommendation carrying a proposed version (F5)" do
      let(:skill) { create(:ai_skill, account: account, effectiveness_score: 0.2) }
      let!(:active_version) do
        create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0", is_active: true)
      end
      let!(:draft_version) do
        create(:ai_skill_version, :evolved, account: account, ai_skill: skill, version: "2.0.0", is_active: false)
      end
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "skill_health",
               target_type: "Ai::Skill",
               target_id: skill.id,
               recommended_config: { "proposed_version_id" => draft_version.id })
      end

      it "activates the proposed version" do
        service.apply_recommendation!(recommendation.id, user: user)

        expect(draft_version.reload.is_active).to be true
        expect(active_version.reload.is_active).to be false
      end

      it "marks the recommendation as applied" do
        service.apply_recommendation!(recommendation.id, user: user)

        expect(recommendation.reload.status).to eq("applied")
      end
    end

    context "with a skill_health recommendation carrying no proposed version (nightly trajectory signal)" do
      let(:skill) { create(:ai_skill, account: account, effectiveness_score: 0.2) }
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "skill_health",
               target_type: "Ai::Skill",
               target_id: skill.id,
               recommended_config: {})
      end

      it "just marks the recommendation applied without error" do
        result = service.apply_recommendation!(recommendation.id, user: user)

        expect(result.status).to eq("applied")
      end
    end

    context "with a skill_creation recommendation from a cluster promotion (P2)" do
      let!(:proposal) do
        create(:ai_skill_proposal, :proposed, account: account, name: "Worktree Lock Guard (learning cluster)",
               category: "productivity",
               metadata: { "source" => "learning_cluster_promotion", "source_learning_ids" => [], "cluster_aggregate" => {} })
      end
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "skill_creation",
               target_type: "Ai::SkillProposal",
               target_id: proposal.id,
               recommended_config: { "skill_proposal_id" => proposal.id })
      end

      it "approves the underlying proposal and creates the skill" do
        service.apply_recommendation!(recommendation.id, user: user)

        proposal.reload
        expect(proposal.status).to eq("created")
        expect(proposal.created_skill).to be_present
      end

      it "marks the recommendation as applied" do
        service.apply_recommendation!(recommendation.id, user: user)

        expect(recommendation.reload.status).to eq("applied")
      end
    end

    context "with a skill_creation recommendation carrying no skill_proposal_id (capability-gap signal, regression)" do
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "skill_creation",
               target_type: "Account",
               target_id: account.id,
               recommended_config: {})
      end

      it "just marks the recommendation applied without error" do
        result = service.apply_recommendation!(recommendation.id, user: user)

        expect(result.status).to eq("applied")
      end
    end

    context "when recommendation does not exist" do
      it "returns nil" do
        result = service.apply_recommendation!(SecureRandom.uuid, user: user)
        expect(result).to be_nil
      end
    end

    context "when recommendation belongs to different account" do
      let(:other_account) { create(:account) }
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: other_account,
               recommendation_type: "provider_switch",
               target_type: "Ai::Agent",
               target_id: agent.id)
      end

      it "returns nil" do
        result = service.apply_recommendation!(recommendation.id, user: user)
        expect(result).to be_nil
      end
    end

    context "when target is not found" do
      let!(:recommendation) do
        create(:ai_improvement_recommendation,
               :pending,
               account: account,
               recommendation_type: "provider_switch",
               target_type: "Ai::Agent",
               target_id: SecureRandom.uuid)
      end

      it "returns nil" do
        result = service.apply_recommendation!(recommendation.id, user: user)
        expect(result).to be_nil
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::ImprovementRecommender, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
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

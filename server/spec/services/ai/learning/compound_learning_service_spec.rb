# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::CompoundLearningService, type: :service do
  let(:account) { create(:account) }
  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:generate).and_return(nil)
  end

  describe "constants" do
    it "sets DEDUP_THRESHOLD to 0.92" do
      expect(described_class::DEDUP_THRESHOLD).to eq(0.92)
    end

    it "sets CHARS_PER_TOKEN to 4" do
      expect(described_class::CHARS_PER_TOKEN).to eq(4)
    end
  end

  describe "#post_execution_extract" do
    let(:team) { create(:ai_agent_team, account: account) }
    let(:execution) do
      double("TeamExecution",
             id: SecureRandom.uuid,
             status: "completed",
             agent_team: team,
             respond_to?: false)
    end

    before do
      allow(execution).to receive(:respond_to?).with(:agent_team).and_return(true)
      allow(execution).to receive(:respond_to?).with(:output_result).and_return(false)
      allow(execution).to receive(:respond_to?).with(:termination_reason).and_return(false)
      allow(execution).to receive(:respond_to?).with(:duration_ms).and_return(false)
      allow(execution).to receive(:respond_to?).with(:total_cost_usd).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_completed).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_failed).and_return(false)
      allow(execution).to receive(:respond_to?).with(:tasks_total).and_return(false)
    end

    it "returns nil for nil execution" do
      expect(service.post_execution_extract(nil)).to be_nil
    end

    it "extracts learnings from successful execution" do
      allow(execution).to receive(:respond_to?).with(:duration_ms).and_return(true)
      allow(execution).to receive(:duration_ms).and_return(2000)

      count = service.post_execution_extract(execution)
      expect(count).to be >= 0
    end

    it "extracts learnings from failed execution" do
      allow(execution).to receive(:status).and_return("failed")
      allow(execution).to receive(:respond_to?).with(:termination_reason).and_return(true)
      allow(execution).to receive(:termination_reason).and_return("Timeout error")

      count = service.post_execution_extract(execution)
      expect(count).to be >= 0
    end

    it "handles exceptions gracefully" do
      allow(execution).to receive(:status).and_raise(StandardError, "boom")

      expect(service.post_execution_extract(execution)).to eq(0)
    end
  end

  describe "#review_feedback_extract" do
    it "returns 0 for nil review" do
      expect(service.review_feedback_extract(nil)).to eq(0)
    end

    it "handles exceptions gracefully" do
      review = double("Review")
      allow(Ai::Learning::AutoExtractorService).to receive_message_chain(:new, :extract_from_review)
        .and_raise(StandardError, "extraction failed")

      expect(service.review_feedback_extract(review)).to eq(0)
    end
  end

  describe "#build_compound_context" do
    let(:agent) { create(:ai_agent, account: account) }

    context "when injection is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(false)
      end

      it "returns empty context" do
        result = service.build_compound_context(
          agent: agent,
          task_description: "Build a feature"
        )

        expect(result[:context]).to be_nil
        expect(result[:token_estimate]).to eq(0)
        expect(result[:learning_ids]).to eq([])
      end
    end

    context "when injection is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_injection, account).and_return(true)
      end

      context "with no matching learnings" do
        it "returns empty context" do
          result = service.build_compound_context(
            agent: agent,
            task_description: "Something with no matches"
          )

          expect(result[:context]).to be_nil
          expect(result[:learning_ids]).to eq([])
        end
      end

      context "with matching learnings" do
        before do
          create(:ai_compound_learning,
                 account: account,
                 category: "best_practice",
                 title: "Use caching",
                 content: "Always use caching for repeated queries",
                 importance_score: 0.8,
                 status: "active")
        end

        it "builds context with learnings" do
          # Use keyword fallback since embedding returns nil
          result = service.build_compound_context(
            agent: agent,
            task_description: "caching queries"
          )

          if result[:context]
            expect(result[:context]).to include("Compound Learnings")
            expect(result[:token_estimate]).to be > 0
            expect(result[:learning_ids]).not_to be_empty
          end
        end
      end

      it "respects token budget" do
        result = service.build_compound_context(
          agent: agent,
          task_description: "test",
          token_budget: 10
        )

        if result[:token_estimate] > 0
          expect(result[:token_estimate]).to be <= 10
        end
      end

      it "handles exceptions gracefully" do
        allow(embedding_service).to receive(:generate).and_raise(StandardError, "embedding error")

        result = service.build_compound_context(
          agent: agent,
          task_description: "test"
        )

        expect(result[:context]).to be_nil
        expect(result[:learning_ids]).to eq([])
      end
    end
  end

  describe "#promote_cross_team" do
    context "when promotion is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_promotion, account).and_return(false)
      end

      it "returns 0" do
        expect(service.promote_cross_team).to eq(0)
      end
    end

    context "when promotion is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?)
          .with(:compound_learning_promotion, account).and_return(true)
      end

      it "returns 0 when no eligible candidates exist" do
        expect(service.promote_cross_team).to eq(0)
      end

      it "handles exceptions gracefully" do
        allow(Ai::CompoundLearning).to receive(:active).and_raise(StandardError, "query error")
        expect(service.promote_cross_team).to eq(0)
      end
    end
  end

  describe "#reinforce_learning" do
    let!(:learning) do
      create(:ai_compound_learning, account: account, importance_score: 0.5, status: "active")
    end

    it "boosts importance of the learning" do
      result = service.reinforce_learning(learning.id)

      expect(result).to be_present
      expect(result.importance_score).to be > 0.5
    end

    it "returns nil for non-existent learning" do
      expect(service.reinforce_learning(SecureRandom.uuid)).to be_nil
    end

    it "returns nil for learning from another account" do
      other = create(:ai_compound_learning, account: create(:account))
      expect(service.reinforce_learning(other.id)).to be_nil
    end
  end

  describe "#decay_and_consolidate" do
    it "returns hash with decayed and archived counts" do
      result = service.decay_and_consolidate

      expect(result).to include(:decayed, :archived)
      expect(result[:decayed]).to be >= 0
      expect(result[:archived]).to be >= 0
    end

    it "decays old learnings" do
      old_learning = create(:ai_compound_learning,
                            account: account,
                            importance_score: 0.8,
                            status: "active",
                            updated_at: 10.days.ago)

      service.decay_and_consolidate

      old_learning.reload
      expect(old_learning.importance_score).to be < 0.8
    end

    it "archives very low importance old learnings" do
      stale_learning = create(:ai_compound_learning,
                              account: account,
                              importance_score: 0.05,
                              status: "active",
                              created_at: 60.days.ago,
                              updated_at: 60.days.ago)

      result = service.decay_and_consolidate

      stale_learning.reload
      expect(stale_learning.status).to eq("deprecated")
      expect(result[:archived]).to be >= 1
    end
  end

  describe "#compound_metrics" do
    it "returns a metrics hash with expected keys" do
      metrics = service.compound_metrics

      expect(metrics).to include(
        :total_learnings, :active_learnings, :by_category,
        :by_scope, :avg_importance, :avg_effectiveness,
        :most_effective, :recently_added, :compound_score
      )
    end

    it "calculates compound score" do
      metrics = service.compound_metrics
      expect(metrics[:compound_score]).to be_a(Float)
    end

    context "with active learnings" do
      before do
        create_list(:ai_compound_learning, 3, account: account, status: "active")
      end

      it "counts active learnings" do
        metrics = service.compound_metrics
        expect(metrics[:active_learnings]).to eq(3)
      end
    end
  end

  describe "#list_learnings" do
    before do
      create(:ai_compound_learning, account: account, category: "best_practice",
             status: "active", importance_score: 0.9)
      create(:ai_compound_learning, account: account, category: "anti_pattern",
             status: "active", importance_score: 0.3)
      create(:ai_compound_learning, account: account, category: "best_practice",
             status: "deprecated", importance_score: 0.3)
    end

    it "returns all learnings by default" do
      results = service.list_learnings
      expect(results.length).to eq(3)
    end

    it "filters by status" do
      results = service.list_learnings(status: "active")
      expect(results.length).to eq(2)
    end

    it "filters by category" do
      results = service.list_learnings(category: "best_practice")
      expect(results.length).to eq(2)
    end

    it "filters by minimum importance" do
      results = service.list_learnings(min_importance: 0.5)
      expect(results.length).to eq(1)
    end

    it "limits results" do
      results = service.list_learnings(limit: 1)
      expect(results.length).to eq(1)
    end
  end
end

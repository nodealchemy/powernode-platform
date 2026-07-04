# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::ScheduledPromotionService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:base_vector) { Array.new(1536, 0.1) }
  let(:near_vector) { base_vector.dup.tap { |v| v[0] = 0.11; v[1] = 0.09 } }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  def make_learning(embedding:, **attrs)
    create(:ai_compound_learning, account: account, embedding: embedding,
                                  confidence_score: 0.8, importance_score: 0.7, **attrs)
  end

  describe "#run" do
    context "when learning_to_skill_promotion is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:learning_to_skill_promotion, account).and_return(false)
      end

      it "returns a skipped result and files no proposals" do
        make_learning(embedding: base_vector, tags: %w[worktree_lock])
        make_learning(embedding: near_vector, tags: %w[worktree_lock])

        expect {
          result = service.run
          expect(result).to eq(skipped: true, reason: "learning_to_skill_promotion feature flag disabled")
        }.not_to change(Ai::SkillProposal, :count)
      end
    end

    context "when learning_to_skill_promotion is enabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:learning_to_skill_promotion, account).and_return(true)
      end

      it "clusters candidates and files a proposal per cluster" do
        make_learning(embedding: base_vector, tags: %w[worktree_lock concurrency])
        make_learning(embedding: near_vector, tags: %w[worktree_lock concurrency])

        result = service.run

        expect(result[:total_clusters]).to eq(1)
        expect(result[:proposed]).to eq(1)
        expect(result[:reused]).to eq(0)
        expect(Ai::SkillProposal.where(account: account).count).to eq(1)
      end

      it "never creates or activates an Ai::Skill itself — propose-only" do
        make_learning(embedding: base_vector, tags: %w[worktree_lock concurrency])
        make_learning(embedding: near_vector, tags: %w[worktree_lock concurrency])

        expect { service.run }.not_to change(Ai::Skill, :count)
      end

      it "is idempotent across runs — a second pass reuses the pending proposal instead of duplicating it" do
        make_learning(embedding: base_vector, tags: %w[worktree_lock concurrency])
        make_learning(embedding: near_vector, tags: %w[worktree_lock concurrency])

        service.run
        result = service.run

        expect(result[:proposed]).to eq(0)
        expect(result[:reused]).to eq(1)
        expect(Ai::SkillProposal.where(account: account).count).to eq(1)
      end

      it "returns zeroed counts when no cluster meets the minimum size" do
        make_learning(embedding: base_vector, tags: %w[lonely_topic])

        result = service.run

        expect(result[:total_clusters]).to eq(0)
        expect(result[:proposed]).to eq(0)
        expect(result[:reused]).to eq(0)
      end

      it "surfaces a clustering failure without raising" do
        allow_any_instance_of(Ai::Learning::LearningClusterService).to receive(:cluster)
          .and_return(success: false, error: "boom", clusters: [], unclustered_learning_ids: [], total_candidates: 0)

        result = service.run

        expect(result).to eq(error: "boom", proposed: 0, reused: 0, total_clusters: 0)
      end

      it "keeps clustering+proposing remaining clusters when one cluster's proposal fails" do
        make_learning(embedding: base_vector, tags: %w[worktree_lock concurrency])
        make_learning(embedding: near_vector, tags: %w[worktree_lock concurrency])

        allow_any_instance_of(Ai::Learning::LearningToSkillPromoter).to receive(:propose_from_cluster)
          .and_raise(StandardError, "propose exploded")

        expect { result = service.run; expect(result[:proposed]).to eq(0) }.not_to raise_error
      end
    end
  end
end

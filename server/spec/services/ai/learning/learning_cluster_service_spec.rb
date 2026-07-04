# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::LearningClusterService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  # All-0.1 vectors with a tiny perturbation cosine-similarity to ~1.0;
  # an alternating +0.1/-0.1 vector is exactly orthogonal (dot product 0)
  # to the base vector, so it's deterministically dissimilar regardless of
  # the configured threshold — no live embedding backend involved.
  let(:base_vector) { Array.new(1536, 0.1) }
  let(:near_vector) do
    base_vector.dup.tap { |v| v[0] = 0.11; v[1] = 0.09 }
  end
  let(:orthogonal_vector) { Array.new(1536) { |i| i.even? ? 0.1 : -0.1 } }

  def make_learning(embedding:, **attrs)
    create(:ai_compound_learning, account: account, embedding: embedding,
                                   confidence_score: 0.8, importance_score: 0.7, **attrs)
  end

  describe "#cluster" do
    it "groups semantically-related learnings into one cluster and leaves a dissimilar learning unclustered" do
      a = make_learning(embedding: base_vector, tags: %w[worktree_lock concurrency])
      b = make_learning(embedding: near_vector, tags: %w[worktree_lock concurrency])
      c = make_learning(embedding: orthogonal_vector, tags: %w[unrelated_topic])

      result = service.cluster

      expect(result[:success]).to be true
      expect(result[:total_candidates]).to eq(3)
      expect(result[:clusters].size).to eq(1)

      cluster = result[:clusters].first
      expect(cluster[:member_ids]).to match_array([a.id, b.id])
      expect(cluster[:member_count]).to eq(2)
      expect(cluster[:label]).to eq("Worktree Lock / Concurrency")

      expect(result[:unclustered_learning_ids]).to contain_exactly(c.id)
    end

    it "excludes retired and low-quality (below the C2 confidence/effectiveness bars) learnings from clustering" do
      good_a = make_learning(embedding: base_vector)
      good_b = make_learning(embedding: near_vector)
      retired = make_learning(embedding: base_vector, status: "retired")
      low_confidence = make_learning(embedding: base_vector, confidence_score: 0.5)
      low_effectiveness = make_learning(embedding: base_vector, effectiveness_score: 0.1)

      result = service.cluster

      expect(result[:total_candidates]).to eq(2)
      surfaced_ids = result[:clusters].flat_map { |c| c[:member_ids] } + result[:unclustered_learning_ids]
      expect(surfaced_ids).to match_array([good_a.id, good_b.id])
      expect(surfaced_ids).not_to include(retired.id, low_confidence.id, low_effectiveness.id)
    end

    it "computes aggregate outcome stats correctly for a cluster" do
      make_learning(
        embedding: base_vector, importance_score: 0.6, confidence_score: 0.8,
        effectiveness_score: 0.6, injection_count: 2,
        positive_outcome_count: 3, negative_outcome_count: 1
      )
      make_learning(
        embedding: near_vector, importance_score: 0.8, confidence_score: 0.9,
        effectiveness_score: nil, injection_count: 1,
        positive_outcome_count: 2, negative_outcome_count: 0
      )

      result = service.cluster
      cluster = result[:clusters].first

      expect(cluster[:member_count]).to eq(2)
      expect(cluster[:aggregate][:total_positive_outcome_count]).to eq(5)
      expect(cluster[:aggregate][:total_negative_outcome_count]).to eq(1)
      expect(cluster[:aggregate][:total_injection_count]).to eq(3)
      expect(cluster[:aggregate][:mean_confidence_score]).to eq(0.85)
      # Only the non-nil effectiveness_score (0.6) contributes to the mean.
      expect(cluster[:aggregate][:mean_effectiveness_score]).to eq(0.6)
      # injection_count < 5 for both members, so effective_importance ==
      # importance_score (see Ai::CompoundLearning#effective_importance).
      expect(cluster[:aggregate][:mean_importance_score]).to eq(0.7)
      expect(cluster[:aggregate][:mean_effective_importance]).to eq(0.7)
    end

    it "returns an empty result when there are no quality candidates" do
      result = service.cluster

      expect(result).to include(success: true, clusters: [], unclustered_learning_ids: [], total_candidates: 0)
    end

    it "respects an explicit similarity_threshold override" do
      make_learning(embedding: base_vector)
      make_learning(embedding: near_vector)

      # near_vector's cosine similarity to base_vector is just under 1.0 but
      # not exactly 1.0 — an unreasonably strict threshold forces them apart.
      result = service.cluster(similarity_threshold: 0.999999999)

      expect(result[:clusters]).to be_empty
      expect(result[:unclustered_learning_ids].size).to eq(2)
    end

    it "honors a DB-driven min_cluster_size from Account#settings" do
      account.update!(settings: { "ai_learning_cluster_min_size" => 1 })
      make_learning(embedding: orthogonal_vector)

      result = service.cluster

      expect(result[:clusters].size).to eq(1)
      expect(result[:clusters].first[:member_count]).to eq(1)
      expect(result[:unclustered_learning_ids]).to be_empty
    end
  end
end

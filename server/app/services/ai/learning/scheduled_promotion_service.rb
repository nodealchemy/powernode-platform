# frozen_string_literal: true

module Ai
  module Learning
    # P3 capstone: closes the learning-to-skill-promotion campaign's loop by
    # turning P1's cluster candidates into P2's operator-review promotion
    # proposals on a schedule. Mirrors Ai::SkillGraph::EvolutionProposalService
    # (F5) / CompoundLearningService#verify_unverified_batch (C4): a thin
    # scheduled orchestrator gated behind its own feature flag, independent of
    # the propose/apply primitives it calls (LearningClusterService#cluster,
    # LearningToSkillPromoter#propose_from_cluster) which stay usable
    # on-demand regardless of this flag. Never applies a proposal or mutates a
    # learning itself — applying (and the P3 supersede-on-approval it
    # triggers) stays gated behind the SkillProposal approve step, see
    # LearningToSkillPromoter#apply_approved_proposal!.
    class ScheduledPromotionService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      def run
        return skipped_result unless Shared::FeatureFlagService.enabled?(:learning_to_skill_promotion, account)

        clustered = cluster_service.cluster
        return cluster_failed_result(clustered) unless clustered[:success]

        proposed = 0
        reused = 0

        clustered[:clusters].each do |cluster|
          outcome = promoter.propose_from_cluster(cluster)
          outcome[:reused] ? (reused += 1) : (proposed += 1)
        rescue StandardError => e
          Rails.logger.warn "[ScheduledPromotionService] propose failed for cluster #{cluster[:cluster_id]}: #{e.message}"
        end

        result = {
          proposed: proposed,
          reused: reused,
          total_clusters: clustered[:clusters].size,
          ran_at: Time.current.iso8601
        }
        Rails.logger.info "[Learning::ScheduledPromotion] #{result.inspect}"
        result
      end

      private

      def skipped_result
        { skipped: true, reason: "learning_to_skill_promotion feature flag disabled" }
      end

      def cluster_failed_result(clustered)
        { error: clustered[:error], proposed: 0, reused: 0, total_clusters: 0 }
      end

      def cluster_service
        @cluster_service ||= Ai::Learning::LearningClusterService.new(account: account)
      end

      def promoter
        @promoter ||= Ai::Learning::LearningToSkillPromoter.new(account: account)
      end
    end
  end
end

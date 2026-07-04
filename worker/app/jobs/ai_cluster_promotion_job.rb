# frozen_string_literal: true

# Recurring scheduler for the P3 learning-cluster -> skill promotion pass.
# The clustering + proposal writes happen server-side
# (Ai::Learning::LearningClusterService#cluster + Ai::Learning::
# LearningToSkillPromoter#propose_from_cluster, gated behind
# :learning_to_skill_promotion) — this job only triggers it on a cron,
# mirroring AiSkillEvolutionProposalJob / AiLearningVerificationJob.
# Propose-only: never creates or activates a skill itself (that stays
# behind the SkillProposal approve->apply gate), so it's safe to run on its
# own schedule independent of the apply/approve flow.
class AiClusterPromotionJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute
    log_info("[ClusterPromotion] Starting scheduled learning cluster promotion pass")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/cluster_promotion_maintenance")
    end

    log_info("[ClusterPromotion] Pass completed successfully")
  end
end

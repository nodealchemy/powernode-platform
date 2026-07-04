# frozen_string_literal: true

# Recurring scheduler for the C4 scheduled learning verify/dispute pass. The
# heuristic scan + verify!/disprove! writes happen server-side
# (Ai::Learning::CompoundLearningService#verify_unverified_batch, gated behind
# :compound_learning_scheduled_verification) — this job only triggers it on a
# cron, mirroring AiSkillEvolutionProposalJob / AiCompoundLearningMaintenanceJob.
class AiLearningVerificationJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute
    log_info("[LearningVerification] Starting scheduled learning verification pass")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/verify_maintenance")
    end

    log_info("[LearningVerification] Verification pass completed successfully")
  end
end

# frozen_string_literal: true

# Recurring scheduler for the F5 skill-health-driven evolution proposer. The
# scan (low-effectiveness skills, active conflicts) and the proposal writes
# happen server-side (Ai::SkillGraph::EvolutionProposalService, gated behind
# :skill_scheduled_evolution) — this job only triggers it on a cron, mirroring
# AiSkillLifecycleMaintenanceJob / AiCampaignDiscoveryJob. Propose-only: never
# activates a version or resolves a conflict, so it's safe to run on its own
# schedule independent of the (default-off) maintenance/auto-resolve flags.
class AiSkillEvolutionProposalJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute
    log_info("[SkillEvolutionProposal] Starting scheduled evolution-proposal scan")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/skill_graph/evolution_proposals")
    end

    log_info("[SkillEvolutionProposal] Scan completed successfully")
  end
end

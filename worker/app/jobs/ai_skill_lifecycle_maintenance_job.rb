# frozen_string_literal: true

class AiSkillLifecycleMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(operation = 'daily')
    log_info("[SkillLifecycleMaintenance] Starting #{operation} maintenance")

    response = with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/skill_graph/maintenance/#{operation}")
    end

    # IMP-89bf582d6ee5: the server gates all maintenance on the
    # skill_optimization feature flag (default OFF) and reports
    # {skipped:, reason:} — which this job used to discard, logging
    # success over months of no-op crons. Surface the skip LOUDLY.
    # Deliberately logging-only: enabling the flag stays an explicit
    # operator decision.
    data = response.is_a?(Hash) ? (response['data'] || {}) : {}
    if data['skipped']
      reason = data['reason'] || 'skipped by server'
      log_warn(
        "[SkillLifecycleMaintenance] #{operation} maintenance DID NOT RUN — #{reason}. " \
        'Enable the skill_optimization feature flag to activate these crons.'
      )
      return { skipped: true, reason: reason }
    end

    log_info("[SkillLifecycleMaintenance] #{operation} maintenance completed successfully")
    { skipped: false }
  end
end

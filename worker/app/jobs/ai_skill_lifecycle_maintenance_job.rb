# frozen_string_literal: true

class AiSkillLifecycleMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(operation = 'daily')
    log_info("[SkillLifecycleMaintenance] Starting #{operation} maintenance")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/skill_graph/maintenance/#{operation}")
    end

    log_info("[SkillLifecycleMaintenance] #{operation} maintenance completed successfully")
  end
end

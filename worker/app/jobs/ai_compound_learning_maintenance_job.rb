# frozen_string_literal: true

class AiCompoundLearningMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[CompoundLearningMaintenance] Starting daily compound learning maintenance")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/compound_maintenance")
    end

    log_info("[CompoundLearningMaintenance] Maintenance completed successfully")
  end
end

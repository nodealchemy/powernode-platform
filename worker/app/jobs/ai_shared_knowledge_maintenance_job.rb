# frozen_string_literal: true

class AiSharedKnowledgeMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[SharedKnowledgeMaintenance] Starting shared knowledge maintenance")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/shared_maintenance")
    end

    log_info("[SharedKnowledgeMaintenance] Shared knowledge maintenance completed successfully")
  end
end

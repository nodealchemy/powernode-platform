# frozen_string_literal: true

class AiMemoryMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[MemoryMaintenance] Starting daily memory maintenance (consolidation, decay, rot detection)")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/learning/memory_maintenance")
    end

    log_info("[MemoryMaintenance] Maintenance completed successfully")
  end
end

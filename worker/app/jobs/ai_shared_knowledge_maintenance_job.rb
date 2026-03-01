# frozen_string_literal: true

class AiSharedKnowledgeMaintenanceJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[SharedKnowledgeMaintenance] Starting shared knowledge maintenance")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/memory/shared_maintenance")
    end

    log_info("[SharedKnowledgeMaintenance] Shared knowledge maintenance completed successfully")

    run_quality_audit
  end

  private

  def run_quality_audit
    log_info("[SharedKnowledgeMaintenance] Running knowledge quality audit")

    response = with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/memory/shared_knowledge", params: { per_page: 1 })
    end

    # Log quality audit summary from the maintenance results
    # The server-side shared_maintenance endpoint handles recalculation,
    # so this audit step provides visibility into the post-maintenance state
    stats = response.dig("data", "stats") || response.dig("stats") || {}
    total = stats["total_entries"] || stats["total"] || 0
    avg_quality = stats["avg_quality_score"] || 0

    log_info("[SharedKnowledgeMaintenance] Quality audit complete",
             total_entries: total,
             avg_quality_score: avg_quality)
  rescue StandardError => e
    # Quality audit is non-critical — log and continue
    log_warn("[SharedKnowledgeMaintenance] Quality audit failed (non-critical): #{e.message}")
  end
end

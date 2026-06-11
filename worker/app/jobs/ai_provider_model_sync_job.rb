# frozen_string_literal: true

# Background job to sync AI provider models and pricing from upstream APIs.
# Runs daily (early morning UTC) as the full-sweep backstop;
# AiProviderPendingSyncJob handles prompt pickup of providers flagged
# sync-pending by their create/update callbacks.
class AiProviderModelSyncJob < BaseJob
  sidekiq_options queue: :ai_orchestration

  def execute
    log_info("Starting AI Provider Model Sync")

    begin
      response = with_api_retry do
        api_client.post("/api/v1/internal/ai/providers/sync_all", { force_refresh: true })
      end

      results = response["results"] || {}
      log_info("Provider model sync completed",
        synced: results["synced"],
        failed: results["failed"],
        skipped: results["skipped"])

      results
    rescue StandardError => e
      log_error("AI Provider Model Sync failed", e)
      raise
    end
  end
end

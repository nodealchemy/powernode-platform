# frozen_string_literal: true

# Background job to sync AI provider models and pricing from upstream APIs
# Runs every 6 hours to keep model lists and pricing up to date
class AiProviderModelSyncJob < BaseJob
  sidekiq_options queue: :ai_workflow_health

  def execute
    log_info("Starting AI Provider Model Sync")

    begin
      response = with_api_retry do
        api_client.post("ai/providers/sync_all", { force_refresh: true })
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

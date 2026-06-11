# frozen_string_literal: true

# Short-interval pull sweep for provider model sync. Providers flag
# themselves sync-pending on create/update (metadata stamp set by their
# after_commit — the callback no longer fetches models inline); this job
# picks the flags up within minutes via the internal API. The daily
# AiProviderModelSyncJob full sweep remains the backstop.
class AiProviderPendingSyncJob < BaseJob
  sidekiq_options queue: "ai_orchestration"

  def execute
    response = with_api_retry do
      api_client.post("/api/v1/internal/ai/providers/sync_pending", {})
    end

    results = response["results"] || {}
    if results["synced"].to_i.positive? || results["failed"].to_i.positive?
      log_info("Pending provider model sync completed",
        synced: results["synced"],
        failed: results["failed"])
    end

    results
  rescue StandardError => e
    log_error("Pending provider model sync failed", e)
    raise
  end
end

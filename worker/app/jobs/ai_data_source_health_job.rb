# frozen_string_literal: true

# AiDataSourceHealthJob - thin cron trigger for the data-source health sweep.
#
# Per the worker architecture, the health-status recompute runs server-side in
# Ai::DataSources::MonitorService#health_tick. This job only POSTs the internal
# health tick endpoint (mTLS) and logs the result. Runs every 10 minutes (see
# config/sidekiq.yml).
class AiDataSourceHealthJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(_args = {})
    log_info "[AiDataSourceHealthJob] Triggering data-source health tick"

    response = api_client.post("/api/v1/internal/ai/data_sources/health_tick", {})
    data = response["data"] || {}

    log_info "[AiDataSourceHealthJob] Health tick complete: " \
             "refreshed=#{data['refreshed'] || 0} errors=#{Array(data['errors']).size}"

    {
      refreshed: data["refreshed"] || 0,
      errors: Array(data["errors"]).size
    }
  rescue StandardError => e
    log_error "[AiDataSourceHealthJob] Health tick failed", e
    raise
  end
end

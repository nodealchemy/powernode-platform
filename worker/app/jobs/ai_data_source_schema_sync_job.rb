# frozen_string_literal: true

# AiDataSourceSchemaSyncJob - thin cron trigger for the data-source schema sync.
#
# Per the worker architecture, ALL sampling/inference/version-recording logic
# runs server-side in Ai::DataSources::SchemaSyncService. This job only POSTs the
# internal schema-sync tick endpoint (mTLS) and logs the batch summary. Runs
# nightly at 04:00 (see config/sidekiq.yml).
class AiDataSourceSchemaSyncJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(args = {})
    limit = args.is_a?(Hash) ? args["limit"] || args[:limit] : nil

    log_info "[AiDataSourceSchemaSyncJob] Triggering data-source schema sync tick"

    payload = {}
    payload[:limit] = limit if limit

    response = api_client.post("/api/v1/internal/ai/data_sources/schema_sync_tick", payload)
    data = response["data"] || {}

    log_info "[AiDataSourceSchemaSyncJob] Schema sync tick complete: " \
             "synced=#{data['synced'] || 0} errors=#{Array(data['errors']).size}"

    {
      synced: data["synced"] || 0,
      errors: Array(data["errors"]).size
    }
  rescue StandardError => e
    log_error "[AiDataSourceSchemaSyncJob] Schema sync tick failed", e
    raise
  end
end

# frozen_string_literal: true

# AiDataSourceMonitorJob - thin cron trigger for the data-source monitor loop.
#
# Per the worker architecture, ALL poll/fetch/change-detect/signal logic runs
# server-side in Ai::DataSources::MonitorService. This job only POSTs the
# internal monitor tick endpoint (mTLS) and logs the batch summary. Runs every
# 5 minutes (see config/sidekiq.yml).
class AiDataSourceMonitorJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 1

  def execute(args = {})
    limit = args.is_a?(Hash) ? args["limit"] || args[:limit] : nil

    log_info "[AiDataSourceMonitorJob] Triggering data-source monitor tick"

    payload = {}
    payload[:limit] = limit if limit

    response = api_client.post("/api/v1/internal/ai/data_sources/monitor_tick", payload)
    data = response["data"] || {}

    log_info "[AiDataSourceMonitorJob] Monitor tick complete: " \
             "polled=#{data['polled'] || 0} changed=#{data['changed'] || 0} " \
             "errors=#{Array(data['errors']).size}"

    {
      polled: data["polled"] || 0,
      changed: data["changed"] || 0,
      errors: Array(data["errors"]).size
    }
  rescue StandardError => e
    log_error "[AiDataSourceMonitorJob] Monitor tick failed", e
    raise
  end
end

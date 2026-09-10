# frozen_string_literal: true

# D1 — the improvement-discovery clock.
#
# The audit's finding (2026-09-10, §6.2): improvement discovery had NO scheduled
# driver. `platform.discover_improvements` returns guidance text naming the
# analyzers a caller should run, and no cron referenced it or them — so the
# platform could not surface a code-quality offer without a human-driven
# session.
#
# The worker only holds the clock. The server owns the analyzers, the per-account
# kill switch, the environment ceiling and the filing, because the worker is
# API-only and the analyzer needs a working copy on the node that holds the
# repository row.
class AiImprovementDiscoveryJob < BaseJob
  sidekiq_options queue: "maintenance", retry: 1

  def execute(params = {})
    log_info("Starting improvement discovery sweep")

    response = with_api_retry { api_client.post("/api/v1/internal/ai/improvement_discovery/run", params) }

    unless response["success"]
      log_warn("Improvement discovery returned no result")
      return
    end

    data = response["data"] || {}
    log_info("Improvement discovery completed",
             accounts_processed: data["accounts_processed"],
             accounts_skipped: data["accounts_skipped"],
             findings: data["findings"],
             offers_created: data["offers_created"],
             offers_deduped: data["offers_deduped"])

    # A linter that never ran reports zero findings exactly like a clean one.
    # Surfacing the degraded list keeps "found nothing" and "analysed nothing"
    # from reading the same in the logs.
    degraded = Array(data["analyzers_degraded"])
    log_warn("Improvement discovery ran with degraded analyzers", degraded: degraded) if degraded.any?

    data
  rescue StandardError => e
    log_error("Improvement discovery failed", e)
    raise
  end
end

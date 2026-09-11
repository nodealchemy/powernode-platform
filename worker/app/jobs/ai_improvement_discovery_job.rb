# frozen_string_literal: true

# D1 — the improvement-discovery clock.
#
# The audit's finding (2026-09-10, §6.2): improvement discovery had NO scheduled
# driver. `platform.discover_improvements` returns guidance text naming the
# analyzers a caller should run, and no cron referenced it or them — so the
# platform could not surface a code-quality offer without a human-driven
# session.
#
# The worker only holds the clock. The server owns the per-account kill switch,
# the environment ceiling and the filing, because the worker is API-only. The
# server does not run the linters either (D1b): each unit hands one account's
# repositories to the registered discovery executor, and the results come back
# to the server later.
class AiImprovementDiscoveryJob < BaseJob
  # No Sidekiq retry (D1 review H2): a retried tick re-runs every unit's
  # sweep. Discovery is weekly and dedupes by fingerprint, so a failed tick
  # waits for the next one.
  sidekiq_options queue: "maintenance", retry: 0

  PATH = "/api/v1/internal/ai/improvement_discovery/run"

  # Per-call HTTP timeout, seconds. One unit is one account's dispatch: a
  # runner lease and a dispatch call, not the linters themselves.
  UNIT_TIMEOUT = 600

  # A backstop on a runaway walk, far above any real fleet.
  MAX_UNITS = 10_000

  def execute(params = {})
    log_info("Starting improvement discovery sweep")
    totals = Hash.new(0)
    degraded = 0
    position = 0

    MAX_UNITS.times do
      # post_no_retry, and NOT wrapped in with_api_retry: each call has a side
      # effect (a sweep that files offers), and the retrying connection plus the
      # job-level retry used to multiply one slow tick into many concurrent
      # sweeps (review H2).
      response = api_client.post_no_retry(PATH, { "position" => position }, timeout: UNIT_TIMEOUT)
      unless response["success"]
        log_warn("Improvement discovery unit returned no result", position: position)
        break
      end

      data = response["data"] || {}
      if data["ran_unit"]
        totals["units"] += 1
        %w[findings offers_created offers_deduped offers_parked].each { |key| totals[key] += data[key].to_i }
        totals["units_#{data['status']}"] += 1 if data["status"]
        degraded += data["analyzers_degraded"].to_i
      end
      break if data["done"]

      position = data["next_position"].to_i
    end

    log_info("Improvement discovery completed", **totals.transform_keys(&:to_sym))
    # A linter that never ran reports zero findings exactly like a clean one.
    log_warn("Improvement discovery ran with degraded analyzers", degraded: degraded) if degraded.positive?
    totals
  rescue BackendApiClient::ApiError => e
    # A cut-off unit may still be running on the server. Ending the tick here
    # means the next unit never overlaps it; the next weekly tick starts over
    # and dedupe absorbs any repeat.
    unless e.status == 408
      log_error("Improvement discovery failed", e)
      raise
    end

    log_warn("Improvement discovery unit timed out; ending this tick", position: position)
    totals
  rescue StandardError => e
    log_error("Improvement discovery failed", e)
    raise
  end
end

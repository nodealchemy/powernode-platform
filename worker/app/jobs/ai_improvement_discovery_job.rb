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
  TIMED_OUT_PATH = "/api/v1/internal/ai/improvement_discovery/timed_out"

  # Where the next tick starts (D1 re-verify). A unit that times out ends the
  # tick, so without a cursor the next tick restarted at unit one and one slow
  # unit starved every unit after it, every week. The cursor moves past a
  # timed-out unit; the walk starts there and wraps round to the units before
  # it, so every unit is reached in the same tick or the next.
  CURSOR_KEY = "ai_improvement_discovery:cursor"

  # The timed-out record is a small write; it must not wait out a unit's bound.
  TIMED_OUT_TIMEOUT = 30

  # Per-call HTTP timeout, seconds. One unit is one account's dispatch: a
  # runner lease and a dispatch call, not the linters themselves.
  UNIT_TIMEOUT = 600

  # A backstop on a runaway walk, far above any real fleet.
  MAX_UNITS = 10_000

  def execute(params = {})
    log_info("Starting improvement discovery sweep")
    totals = Hash.new(0)
    degraded = 0
    start = read_cursor
    position = start
    wrapped = start.zero?
    lap_complete = false

    MAX_UNITS.times do
      # post_no_retry, and NOT wrapped in with_api_retry: each call has a side
      # effect, and the retrying connection plus the job-level retry used to
      # multiply one slow tick into many concurrent sweeps (review H2).
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

      if data["done"]
        # The end of the list. A tick that started mid-list wraps round once to
        # the units before its start; one that started at the top is finished.
        if wrapped
          lap_complete = true
          break
        end

        wrapped = true
        position = 0
        break if position >= start

        next
      end

      position = data["next_position"].to_i
      if wrapped && start.positive? && position >= start
        lap_complete = true
        break
      end
    end

    # Only a whole lap resets the cursor. A walk cut short any other way (no
    # result, the runaway backstop) keeps it, so the next tick resumes there.
    write_cursor(0) if lap_complete
    log_info("Improvement discovery completed", **totals.transform_keys(&:to_sym))
    # A linter that never ran reports zero findings exactly like a clean one.
    log_warn("Improvement discovery ran with degraded analyzers", degraded: degraded) if degraded.positive?
    totals
  rescue BackendApiClient::ApiError => e
    unless e.status == 408
      # The platform, not the unit, is failing: keep the cursor, so the unit
      # is tried again next tick.
      log_error("Improvement discovery failed", e)
      raise
    end

    # A cut-off unit may still be running on the server, so the tick ends here
    # and never overlaps it. The unit is recorded as not measured, and the
    # cursor moves past it so the next tick does not restart at unit one.
    record_timed_out(position)
    write_cursor(position + 1)
    log_warn("Improvement discovery unit timed out; ending this tick", position: position)
    totals
  rescue StandardError => e
    log_error("Improvement discovery failed", e)
    raise
  end

  private

  def read_cursor
    Sidekiq.redis { |conn| conn.get(CURSOR_KEY) }.to_i
  rescue StandardError => e
    log_warn("Improvement discovery cursor unreadable; starting at the top", error: e.class.name)
    0
  end

  def write_cursor(position)
    Sidekiq.redis { |conn| conn.set(CURSOR_KEY, position.to_i) }
  rescue StandardError => e
    log_warn("Improvement discovery cursor not saved", error: e.class.name)
  end

  # Best effort: a lost record must not turn a graceful tick end into a failure.
  def record_timed_out(position)
    api_client.post_no_retry(TIMED_OUT_PATH, { "position" => position }, timeout: TIMED_OUT_TIMEOUT)
  rescue StandardError => e
    log_warn("Improvement discovery timeout not recorded", position: position, error: e.class.name)
  end
end

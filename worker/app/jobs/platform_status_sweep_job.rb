# frozen_string_literal: true

# Ticks the component status plane (campaign 01a08c9b, increment A2).
#
# The server runs no Sidekiq, so the CADENCE lives here and the WORK lives on
# the server behind /api/v1/internal/platform/status_sweep. Every gate — the
# per-account kill switch and the dual-plane standby fence — is server side,
# so this cron ticks unconditionally and a halted platform simply reports
# `skipped` with a reason. Same split as AiClosureDriverJob.
#
# ── THE LOCK ────────────────────────────────────────────────────────────────
# Held through the shared DistributedLock concern, which this job was the
# first ever caller of. Using it surfaced a real defect — its release used
# redis-rb's `eval(script, keys:, argv:)` signature, which raises on the
# client Sidekiq 8 hands out, inside a rescue that swallowed it, so the lock
# was never released. That is fixed in the concern (with its own both-arms
# spec against real Redis); this job holds no private copy.
#
# ── WHY A LOCK, AND WHY THE TTL IS FOUR TIMES THE PERIOD ────────────────────
# The sweep is idempotent (it upserts by (account, kind, ref) and only emits
# an event when a verdict actually CHANGES), so an overlap costs work rather
# than correctness. But at a 60-second period a sweep that takes longer than
# 60 seconds would have a second copy start on top of it, then a third, until
# the server spends its whole minute on status sweeps. The lock makes a slow
# sweep skip a tick instead of stacking.
#
# The 240s TTL is deliberately FOUR periods, not one: a TTL at or near the
# period expires while the holder is still working and re-admits exactly the
# pile-up the lock exists to prevent. It is an upper bound on how long a
# CRASHED holder can block the cron, which is the only thing a lock TTL
# should be — and four missed ticks is survivable, because the server's reap
# grace is three sweeps and a missed sweep leaves rows with the verdicts they
# already had.
class PlatformStatusSweepJob < BaseJob
  include DistributedLock

  sidekiq_options queue: :default, retry: 1

  # DistributedLock namespaces this as "lock:<key>" in Redis, so the live key
  # is "lock:platform:status:sweep:lock".
  LOCK_KEY = 'platform:status:sweep:lock'
  LOCK_TTL_SECONDS = 240

  SWEEP_PATH = '/api/v1/internal/platform/status_sweep'

  def execute(_args = {})
    result = with_lock(LOCK_KEY, ttl: LOCK_TTL_SECONDS) { sweep! }

    if result.nil?
      # `with_lock` returns nil when the lock was not acquired. Not an error:
      # the previous tick is still running and this one is correctly skipped.
      # BaseJob#perform also treats a { skipped: true } result as "did not
      # run" for its execution accounting.
      log_info '[PlatformStatusSweepJob] previous sweep still running, skipping this tick'
      return { skipped: true, reason: 'lock_held' }
    end

    result
  end

  private

  def sweep!
    response = api_client.post(SWEEP_PATH, {})
    data = response['data'] || {}
    summaries = data['summaries'] || []

    skipped = summaries.count { |s| s['skipped'] }
    transitions = summaries.sum { |s| s['transitions'].to_i }
    events = summaries.sum { |s| s['events_written'].to_i }

    if data['truncated']
      # The server stopped early on its own wall-clock ceiling. Worth a
      # warning rather than a silent success: it means the installed base has
      # outgrown one tick, and the leftovers wait for the next one.
      log_warn "[PlatformStatusSweepJob] server truncated the sweep after #{data['duration_seconds']}s"
    end

    log_info "[PlatformStatusSweepJob] #{data['accounts_swept'].to_i} account(s), " \
             "#{skipped} skipped, #{transitions} transition(s), #{events} event(s), " \
             "#{data['events_pruned'].to_i} pruned"

    {
      accounts_swept: data['accounts_swept'].to_i,
      accounts_skipped: skipped,
      transitions: transitions,
      events_written: events,
      events_pruned: data['events_pruned'].to_i,
      truncated: data['truncated'] == true
    }
  end
end

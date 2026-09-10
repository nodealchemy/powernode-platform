# frozen_string_literal: true

# Ticks the component status plane (campaign 01a08c9b, increment A2).
#
# The server runs no Sidekiq, so the CADENCE lives here and the WORK lives on
# the server behind /api/v1/internal/platform/status_sweep. Every gate — the
# per-account kill switch and the dual-plane standby fence — is server side,
# so this cron ticks unconditionally and a halted platform simply reports
# `skipped` with a reason. Same split as AiClosureDriverJob.
#
# ── WHY THIS DOES NOT USE THE SHARED DistributedLock CONCERN ────────────────
# app/services/concerns/distributed_lock.rb looks like exactly the right
# thing to reuse, and it is not: its `release_lock` calls
# `conn.eval(script, keys:, argv:)`, which is redis-rb's signature. Sidekiq 8
# hands out a `Sidekiq::RedisClientAdapter::CompatClient`, where that call
# raises `TypeError: Unsupported command argument type: Array` — and
# `release_lock` rescues StandardError and logs, so the failure is invisible
# and THE LOCK IS NEVER RELEASED. It expires only by TTL.
#
# Measured, not inferred: driving the concern from this job left the key
# present after a clean run (`exists` == 1). With a 240s TTL on a 60s cron
# that would have silently skipped three ticks out of every four while
# reporting success. The concern has no other callers, so this was code that
# had never been executed. Fixing it belongs to whoever owns that file;
# this job holds its own lock rather than depending on a broken one.
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
  sidekiq_options queue: :default, retry: 1

  LOCK_KEY = 'platform:status:sweep:lock'
  LOCK_TTL_SECONDS = 240

  SWEEP_PATH = '/api/v1/internal/platform/status_sweep'

  # Delete the key only if we still own it. A plain DEL would let a slow
  # holder, whose TTL expired mid-run, delete the lock a DIFFERENT process has
  # since taken — releasing someone else's lock and re-admitting the overlap.
  RELEASE_SCRIPT = <<~LUA
    if redis.call("get", KEYS[1]) == ARGV[1] then
      return redis.call("del", KEYS[1])
    else
      return 0
    end
  LUA

  def execute(_args = {})
    token = "#{Process.pid}-#{SecureRandom.hex(8)}"

    unless acquire_lock(token)
      # Not an error: the previous tick is still running and this one is
      # correctly skipped. BaseJob#perform also treats a { skipped: true }
      # result as "did not run" for its execution accounting.
      log_info '[PlatformStatusSweepJob] previous sweep still running, skipping this tick'
      return { skipped: true, reason: 'lock_held' }
    end

    begin
      sweep!
    ensure
      release_lock(token)
    end
  end

  private

  def redis_lock_key
    "lock:#{LOCK_KEY}"
  end

  def acquire_lock(token)
    Sidekiq.redis { |conn| conn.set(redis_lock_key, token, nx: true, ex: LOCK_TTL_SECONDS) }
  end

  # Never raises: a failure to release costs at most one TTL of skipped ticks,
  # whereas raising here would mask the sweep's own result (or its exception).
  def release_lock(token)
    Sidekiq.redis { |conn| conn.call('EVAL', RELEASE_SCRIPT, 1, redis_lock_key, token) }
  rescue StandardError => e
    log_warn "[PlatformStatusSweepJob] could not release lock: #{e.class}: #{e.message}"
  end

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
             "#{skipped} skipped, #{transitions} transition(s), #{events} event(s)"

    {
      accounts_swept: data['accounts_swept'].to_i,
      accounts_skipped: skipped,
      transitions: transitions,
      events_written: events,
      truncated: data['truncated'] == true
    }
  end
end

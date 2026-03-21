# frozen_string_literal: true

# Safety-net cron job: picks up orphaned pending sessions that weren't dispatched
# immediately (e.g., after a worker crash). Primary dispatch happens at session
# creation time via Redis queue push — see TrainingSessionsController#create.
# Paused session recovery is handled by the overseer decision engine.
class TradingTrainingSessionRunnerJob < BaseJob
  sidekiq_options queue: 'trading_critical', retry: 0

  # Short TTL for dispatch lock — the execution job overwrites with a longer TTL.
  # This just prevents the next cron tick from re-dispatching during setup.
  DISPATCH_LOCK_TTL = 120

  # How old a lock must be before the runner considers it stale (holder dead).
  # Set to match LOCK_TTL: jid_active? is unreliable (misses I/O-blocked
  # threads), so we trust the TTL mechanism for dead-job recovery instead.
  # Dead jobs are recovered within 15 min via natural lock expiry.
  STALE_LOCK_AGE_THRESHOLD = 300

  # Atomic CAS: replace lock value only if it still holds expected_value.
  # Prevents TOCTOU races where del+set NX allows another job to slip in between.
  LOCK_CAS_SCRIPT = <<~LUA
    if redis.call('get', KEYS[1]) == ARGV[1] then
      redis.call('set', KEYS[1], ARGV[2], 'EX', ARGV[3])
      return 1
    else
      return 0
    end
  LUA

  def execute
    clear_stale_locks_from_dead_workers!

    response = api_client.get("/api/v1/internal/trading/pending_training_sessions")
    sessions = response.dig("data", "items") || []
    log_info("Runner found #{sessions.size} resumable sessions")

    dispatched = []

    sessions.each do |session|
      # Skip recently-created pending sessions only if a dispatch lock exists,
      # confirming the controller's immediate dispatch is active. If the lock is
      # missing (e.g., worker restarted after creation), dispatch immediately.
      if session["status"] == "pending"
        created_at = session["created_at"]
        if created_at
          age_seconds = Time.current - (Time.parse(created_at) rescue Time.current)
          if age_seconds < DISPATCH_LOCK_TTL
            lock_key = "training_session_lock:#{session['id']}"
            has_lock = Sidekiq.redis { |conn| conn.call("EXISTS", lock_key) > 0 }
            if has_lock
              log_info("Session too recent (#{age_seconds.round}s) with active lock, skipping", session_id: session["id"])
              next
            end
            log_info("Session too recent but no lock found — dispatching (worker restart recovery)", session_id: session["id"])
          end
        end
      end

      lock_key = "training_session_lock:#{session["id"]}"

      locking_value = Sidekiq.redis { |conn| conn.get(lock_key) }

      if locking_value
        if locking_value == "dispatching" || jid_active?(locking_value)
          log_info("Training session locked (#{locking_value}), skipping", session_id: session["id"])
          next
        else
          # jid_active? returned false — but Sidekiq::Workers can miss busy threads
          # (heartbeat lag, I/O-blocked threads). Use lock TTL as a secondary signal:
          # if the lock was recently set or renewed, the holder is almost certainly alive.
          # Threshold is generous (10 min) because individual setup phases can block
          # 300s+ when the backend serializes via Postgres advisory lock.
          lock_ttl = Sidekiq.redis { |conn| conn.ttl(lock_key) }
          lock_age = TradingTrainingSessionJob::LOCK_TTL - [lock_ttl, 0].max
          if lock_age < STALE_LOCK_AGE_THRESHOLD
            log_info("Lock still fresh (age: #{lock_age}s), skipping despite jid_active? miss",
                     session_id: session["id"], lock_holder: locking_value)
            next
          end

          # Dead JID with decayed lock — atomic CAS: replace with "dispatching" only if still the dead JID.
          # This closes the TOCTOU window where del + set NX allowed another job to slip in.
          replaced = Sidekiq.redis { |conn|
            conn.call("EVAL", LOCK_CAS_SCRIPT, 1, lock_key, locking_value, "dispatching", DISPATCH_LOCK_TTL.to_s)
          }
          unless replaced == 1
            log_info("Stale lock changed while clearing, skipping", session_id: session["id"])
            next
          end
          log_info("Replaced stale lock from dead JID #{locking_value} with dispatch sentinel", session_id: session["id"])
          TradingTrainingSessionJob.perform_async(session["id"])
          dispatched << session["id"]
          next
        end
      end

      # No lock exists — acquire and dispatch
      acquired = Sidekiq.redis { |conn| conn.set(lock_key, "dispatching", nx: true, ex: DISPATCH_LOCK_TTL) }

      unless acquired
        log_info("Lock race lost, another dispatch in progress", session_id: session["id"])
        next
      end

      log_info("Dispatching training session", session_id: session["id"], name: session["name"],
               completed_ticks: session["completed_ticks"])
      TradingTrainingSessionJob.perform_async(session["id"])
      dispatched << session["id"]
    end

    { pending_count: sessions.size, dispatched: dispatched }
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("Backend unavailable, skipping session runner (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("Session runner skipped: #{e.message}")
  end

  private

  def jid_active?(check_jid)
    Sidekiq::Workers.new.each do |_, _, work|
      next unless work.is_a?(Hash)

      jid = work.dig("payload", "jid") || work["jid"]
      return true if jid == check_jid
    end
    false
  rescue StandardError
    true # Assume active if we can't check — safer to skip than double-dispatch
  end

  # Proactive stale lock scan: after a worker restart, the old worker's JIDs
  # no longer exist. Scan all training_session_lock:* keys and clear any held
  # by JIDs that aren't in the current worker process. Uses a 5-minute threshold
  # because jid_active? is unreliable for I/O-blocked threads (batch context
  # fetch can block 60-120s while appearing idle to Sidekiq::Workers).
  def clear_stale_locks_from_dead_workers!
    cleared = 0
    Sidekiq.redis do |conn|
      # keys is safe here — at most ~20 training session locks exist at any time
      lock_keys = conn.keys("training_session_lock:*")
      lock_keys.each do |key|
        holder = conn.get(key)
        next if holder.nil? || holder == "dispatching"
        next if jid_active?(holder)

        lock_ttl = conn.ttl(key)
        lock_age = TradingTrainingSessionJob::LOCK_TTL - [lock_ttl, 0].max
        next if lock_age < 300 # 5 min — batch context fetch for large sessions takes 60-120s

        conn.del(key)
        cleared += 1
        log_info("Cleared stale lock from dead JID #{holder}", lock_key: key, age: lock_age)
      end
    end
    log_info("Stale lock scan complete: #{cleared} locks cleared") if cleared > 0
  rescue StandardError => e
    log_warn("Stale lock scan failed (non-fatal): #{e.message}")
  end
end

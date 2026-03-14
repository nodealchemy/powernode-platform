# frozen_string_literal: true

# Safety-net cron job: picks up orphaned pending/paused sessions that weren't dispatched
# immediately (e.g., after a worker crash). Primary dispatch happens at session
# creation time via Redis queue push — see TrainingSessionsController#create.
# Also resumes paused sessions that were auto-paused by orphan recovery.
class TradingTrainingSessionRunnerJob < BaseJob
  sidekiq_options queue: 'trading', retry: 0

  # Short TTL for dispatch lock — the execution job overwrites with a longer TTL.
  # This just prevents the next cron tick from re-dispatching during setup.
  DISPATCH_LOCK_TTL = 120

  # How old a lock must be before the runner considers it stale (holder dead).
  # Set to match LOCK_TTL: jid_active? is unreliable (misses I/O-blocked
  # threads), so we trust the TTL mechanism for dead-job recovery instead.
  # Dead jobs are recovered within 15 min via natural lock expiry.
  STALE_LOCK_AGE_THRESHOLD = 900

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

  # Cooldown after orphan recovery pauses a session — prevents immediate re-dispatch
  # that causes a pause→start→crash→pause bounce cycle.
  PAUSED_COOLDOWN = 300 # 5 minutes — matches STALE_RUNNING_THRESHOLD on the backend

  def execute
    response = api_client.get("/api/v1/internal/trading/pending_training_sessions")
    sessions = response.dig("data", "items") || []
    log_info("Runner found #{sessions.size} resumable sessions")

    dispatched = []

    sessions.each do |session|
      # Skip recently-created pending sessions — the controller dispatches immediately.
      if session["status"] == "pending"
        created_at = session["created_at"]
        if created_at
          age_seconds = Time.current - (Time.parse(created_at) rescue Time.current)
          if age_seconds < DISPATCH_LOCK_TTL
            log_info("Session too recent (#{age_seconds.round}s), immediate dispatch should handle it", session_id: session["id"])
            next
          end
        end
      end

      # Skip recently-paused sessions to prevent bounce cycle:
      # orphan recovery pauses → runner re-dispatches → start! → crash → paused again
      if session["status"] == "paused"
        updated_at = session["updated_at"]
        if updated_at
          pause_age = Time.current - (Time.parse(updated_at) rescue Time.current)
          if pause_age < PAUSED_COOLDOWN
            log_info("Paused session cooling down (#{pause_age.round}s/#{PAUSED_COOLDOWN}s)", session_id: session["id"])
            next
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

      action = session["status"] == "paused" ? "Resuming paused" : "Dispatching"
      log_info("#{action} training session", session_id: session["id"], name: session["name"],
               completed_ticks: session["completed_ticks"])
      TradingTrainingSessionJob.perform_async(session["id"])
      dispatched << session["id"]
    end

    { pending_count: sessions.size, dispatched: dispatched }
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
end

# frozen_string_literal: true

# Safety-net cron job: picks up orphaned pending sessions that weren't dispatched
# immediately (e.g., after a worker crash). Primary dispatch happens at session
# creation time via Redis queue push — see TrainingSessionsController#create.
class TradingTrainingSessionRunnerJob < BaseJob
  sidekiq_options queue: 'trading', retry: 0

  # Short TTL for dispatch lock — the execution job overwrites with a longer TTL.
  # This just prevents the next cron tick from re-dispatching during setup.
  DISPATCH_LOCK_TTL = 120

  def execute
    response = api_client.get("/api/v1/internal/trading/pending_training_sessions")
    sessions = response.dig("data", "items") || []
    log_info("Runner found #{sessions.size} pending sessions")

    dispatched = []

    sessions.each do |session|
      lock_key = "training_session_lock:#{session["id"]}"

      locking_value = Sidekiq.redis { |conn| conn.get(lock_key) }

      if locking_value
        if stale_lock?(locking_value)
          log_info("Clearing stale lock (#{locking_value} no longer active)", session_id: session["id"])
          Sidekiq.redis { |conn| conn.del(lock_key) }
        else
          log_info("Training session actively locked (#{locking_value}), skipping", session_id: session["id"])
          next
        end
      end

      # Acquire lock BEFORE dispatching — prevents race where next cron tick
      # fires before the execution job has a chance to set its own lock.
      acquired = Sidekiq.redis { |conn| conn.set(lock_key, "dispatching", nx: true, ex: DISPATCH_LOCK_TTL) }

      unless acquired
        log_info("Lock race lost, another dispatch in progress", session_id: session["id"])
        next
      end

      log_info("Dispatching training session", session_id: session["id"], name: session["name"])
      TradingTrainingSessionJob.perform_async(session["id"])
      dispatched << session["id"]
    end

    { pending_count: sessions.size, dispatched: dispatched }
  end

  private

  # Check if a lock holder is still actively processing.
  # "dispatching" locks are considered stale after their TTL (handled by Redis expiry).
  # JID-based locks are checked against the Sidekiq busy set.
  def stale_lock?(value)
    return false if value == "dispatching" # Short-lived, let TTL handle it

    # It's a JID — check if it's still in the busy set
    busy_jids = Sidekiq::Workers.new.map { |_, _, work| work["payload"]["jid"] rescue nil }.compact
    !busy_jids.include?(value)
  rescue StandardError => e
    log_warn("Failed to check JID liveness: #{e.message}")
    false # Assume lock is valid if we can't check
  end
end

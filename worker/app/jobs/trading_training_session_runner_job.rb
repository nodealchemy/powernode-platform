# frozen_string_literal: true

class TradingTrainingSessionRunnerJob < BaseJob
  sidekiq_options queue: 'trading', retry: 0

  def execute
    response = api_client.get("/api/v1/internal/trading/pending_training_sessions")
    sessions = response.dig("data", "items") || []
    log_info("Runner found #{sessions.size} pending sessions")

    dispatched = []

    sessions.each do |session|
      lock_key = "training_session_lock:#{session["id"]}"

      locking_jid = Sidekiq.redis { |conn| conn.get(lock_key) }

      if locking_jid
        # Lock exists — check if the holding JID is still actively processing.
        # If the worker was restarted, the old JID won't be in the busy set.
        if stale_lock?(locking_jid)
          log_info("Clearing stale lock (JID #{locking_jid} no longer active)", session_id: session["id"])
          Sidekiq.redis { |conn| conn.del(lock_key) }
        else
          log_info("Training session actively locked by JID #{locking_jid}, skipping", session_id: session["id"])
          next
        end
      end

      log_info("Dispatching training session", session_id: session["id"], name: session["name"])
      TradingTrainingSessionJob.perform_async(session["id"])
      dispatched << session["id"]
    end

    { pending_count: sessions.size, dispatched: dispatched }
  end

  private

  # Check if a JID is still in the Sidekiq busy set (actively executing).
  # Returns true if the JID is NOT found (lock is stale).
  def stale_lock?(jid)
    busy_jids = Sidekiq::Workers.new.map { |_, _, work| work["payload"]["jid"] rescue nil }.compact
    !busy_jids.include?(jid)
  rescue StandardError => e
    log_warn("Failed to check JID liveness: #{e.message}")
    false # Assume lock is valid if we can't check
  end
end

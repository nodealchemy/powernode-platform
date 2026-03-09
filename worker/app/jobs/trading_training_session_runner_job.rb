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

      # Check if this session is already being executed by another job
      already_locked = Sidekiq.redis { |conn| conn.call("EXISTS", lock_key) == 1 }

      if already_locked
        log_info("Training session already locked, skipping dispatch", session_id: session["id"])
      else
        log_info("Dispatching training session", session_id: session["id"], name: session["name"])
        TradingTrainingSessionJob.perform_async(session["id"])
        dispatched << session["id"]
      end
    end

    { pending_count: sessions.size, dispatched: dispatched }
  end
end

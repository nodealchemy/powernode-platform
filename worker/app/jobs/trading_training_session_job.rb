# frozen_string_literal: true

class TradingTrainingSessionJob < BaseJob
  sidekiq_options queue: 'trading', retry: 5

  LOCK_TTL = 7200 # 2 hours — training sessions with many strategies are very long-running

  def execute(session_id)
    lock_key = "training_session_lock:#{session_id}"

    # Acquire exclusive lock to prevent concurrent runs of the same session.
    # NX: only set if key doesn't exist. EX: auto-expire as safety net.
    acquired = Sidekiq.redis { |conn| conn.set(lock_key, jid, nx: true, ex: LOCK_TTL) }

    unless acquired
      log_info("Training session already running, skipping duplicate", session_id: session_id)
      return { skipped: true, reason: "already_running" }
    end

    begin
      log_info("Dispatching training session to backend", session_id: session_id)

      # The backend spawns the training session in a background thread and returns
      # immediately. No need for the 3600s trading_training circuit breaker — the
      # default backend_api breaker (120s) is sufficient for the dispatch call.
      response = api_client.post("/api/v1/internal/trading/run_training_session", {
        session_id: session_id
      })

      if response["success"]
        log_info("Training session dispatched successfully", session_id: session_id,
          status: response.dig("data", "status"))
      else
        log_warn("Training session dispatch failed", session_id: session_id, error: response["error"])
      end

      response
    rescue StandardError => e
      log_error("Training session dispatch failed", e, session_id: session_id)

      begin
        api_client.post("/api/v1/internal/trading/fail_training_session", {
          session_id: session_id,
          error_message: e.message
        })
      rescue StandardError => fail_err
        log_error("Failed to mark session as failed", fail_err, session_id: session_id)
      end

      raise
    ensure
      # Release lock so retries or new sessions can proceed
      Sidekiq.redis { |conn| conn.del(lock_key) }
    end
  end
end

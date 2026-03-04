# frozen_string_literal: true

class AiPressureFieldDecayJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute
    log_info("Starting pressure field decay")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/coordination/decay_fields") }
    decayed = response.dig("data", "decayed") || 0
    log_info("Pressure field decay complete", decayed: decayed)
  rescue StandardError => e
    log_error("Pressure field decay failed", e)
    raise
  end
end

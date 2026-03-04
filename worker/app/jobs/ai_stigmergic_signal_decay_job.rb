# frozen_string_literal: true

class AiStigmergicSignalDecayJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute
    log_info("Starting stigmergic signal decay")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/coordination/decay_signals") }
    decayed = response.dig("data", "decayed") || 0
    log_info("Stigmergic signal decay complete", decayed: decayed)
  rescue StandardError => e
    log_error("Stigmergic signal decay failed", e)
    raise
  end
end

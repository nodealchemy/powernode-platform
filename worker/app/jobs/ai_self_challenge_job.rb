# frozen_string_literal: true

class AiSelfChallengeJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting self-challenge processing", challenge_id: params["challenge_id"])
    response = with_api_retry { api_client.post("/api/v1/internal/ai/self_challenges/process", params) }
    if response["success"]
      log_info("Self-challenge processing completed", result: response.dig("data"))
    else
      log_warn("Self-challenge processing returned no result")
    end
  rescue StandardError => e
    log_error("Self-challenge processing failed", e)
    raise
  end
end

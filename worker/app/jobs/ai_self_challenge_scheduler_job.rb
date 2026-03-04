# frozen_string_literal: true

class AiSelfChallengeSchedulerJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting daily self-challenge scheduling")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/self_challenges/schedule_daily", params) }
    if response["success"]
      log_info("Self-challenge scheduling completed", result: response.dig("data"))
    else
      log_warn("Self-challenge scheduling returned no result")
    end
  rescue StandardError => e
    log_error("Self-challenge scheduling failed", e)
    raise
  end
end

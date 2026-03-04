# frozen_string_literal: true

class AiSkillAutoEvolutionJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting skill auto-evolution", threshold: params["threshold"])
    response = with_api_retry { api_client.post("/api/v1/internal/ai/skills/auto_evolve", params) }
    if response["success"]
      log_info("Skill auto-evolution completed", result: response.dig("data"))
    else
      log_warn("Skill auto-evolution returned no result")
    end
  rescue StandardError => e
    log_error("Skill auto-evolution failed", e)
    raise
  end
end

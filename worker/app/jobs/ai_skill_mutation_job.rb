# frozen_string_literal: true

class AiSkillMutationJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(params = {})
    log_info("Starting skill mutation", skill_id: params["skill_id"], strategy: params["strategy"])
    response = with_api_retry { api_client.post("/api/v1/internal/ai/skills/mutate", params) }
    if response["success"]
      log_info("Skill mutation completed", result: response.dig("data"))
    else
      log_warn("Skill mutation returned no result")
    end
  rescue StandardError => e
    log_error("Skill mutation failed", e)
    raise
  end
end

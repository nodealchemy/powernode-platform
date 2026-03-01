# frozen_string_literal: true

class AiSkillConflictCheckJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  def execute(skill_id)
    log_info("[SkillConflictCheck] Checking conflicts for skill #{skill_id}")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/skill_graph/conflict_check", { skill_id: skill_id })
    end

    log_info("[SkillConflictCheck] Completed for #{skill_id}")
  end
end

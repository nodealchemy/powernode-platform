# frozen_string_literal: true

class AiSkillConflictCheckJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 2

  DEDUP_TTL = 120 # seconds — conflict results don't change faster; headroom above BaseJob's 60s runaway window

  def execute(skill_id)
    idempotency_key = "skill_conflict_check:#{skill_id}"
    if already_processed?(idempotency_key)
      log_info("[SkillConflictCheck] Skipped (dedup) for skill #{skill_id}")
      return
    end

    log_info("[SkillConflictCheck] Checking conflicts for skill #{skill_id}")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/skill_graph/conflict_check", { skill_id: skill_id })
    end

    mark_processed(idempotency_key, ttl: DEDUP_TTL)

    log_info("[SkillConflictCheck] Completed for #{skill_id}")
  end
end

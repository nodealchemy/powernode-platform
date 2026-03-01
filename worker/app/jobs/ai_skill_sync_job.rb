# frozen_string_literal: true

# AiSkillSyncJob - Synchronizes system skills and tracks usage
# Can seed system skills, refresh connectors, or increment usage counters
class AiSkillSyncJob < BaseJob
  sidekiq_options queue: :ai_orchestration, retry: 2

  def execute(args = {})
    @action = args[:action] || args['action'] || 'seed'
    @skill_id = args[:skill_id] || args['skill_id']
    @account_id = args[:account_id] || args['account_id']

    case @action
    when 'seed'
      seed_system_skills
    when 'refresh_connectors'
      refresh_skill_connectors
    else
      raise ArgumentError, "Unknown action: #{@action}"
    end
  end

  private

  def seed_system_skills
    log_info("Seeding system skills via backend API")

    response = api_client.post("/api/v1/internal/ai/skills/seed_system", {})

    if response['success']
      log_info("System skills seeded: #{response.dig('data', 'count') || 'unknown'} skills")
    else
      log_error("Failed to seed system skills", nil, error: response['error'])
      raise "System skill seeding failed: #{response['error']}"
    end

    response['data']
  end

  def refresh_skill_connectors
    raise ArgumentError, "skill_id is required for refresh_connectors" unless @skill_id

    response = api_client.post(
      "/api/v1/internal/ai/skills/#{@skill_id}/refresh_connectors",
      { account_id: @account_id }
    )

    if response['success']
      log_info("Skill connectors refreshed", skill_id: @skill_id)
    else
      log_warn("Failed to refresh connectors", skill_id: @skill_id, error: response['error'])
    end

    response['data']
  end
end

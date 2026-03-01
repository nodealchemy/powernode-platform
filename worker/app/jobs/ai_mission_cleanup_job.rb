# frozen_string_literal: true

class AiMissionCleanupJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_maintenance', retry: 2

  def execute(params)
    validate_required_params(params, 'mission_id')

    mission_id = params['mission_id']
    log_info("Starting mission cleanup", mission_id: mission_id)

    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      log_warn("Could not fetch mission for cleanup", mission_id: mission_id)
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Cleanup deployment if exists
    if mission['deployed_container_id'].present?
      cleanup_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/cleanup_deployment", {
        container_id: mission['deployed_container_id'],
        port: mission['deployed_port']
      })

      if cleanup_result['success']
        log_info("Deployment cleaned up", mission_id: mission_id)
      else
        log_warn("Deployment cleanup failed", error: cleanup_result['error'])
      end
    end

    log_info("Mission cleanup completed", mission_id: mission_id)
  rescue StandardError => e
    log_error("Mission cleanup job failed", exception: e, mission_id: params['mission_id'])
    # Don't re-raise cleanup failures - they shouldn't block anything
  end
end

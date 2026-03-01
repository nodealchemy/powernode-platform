# frozen_string_literal: true

class AiMissionDeployJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission deployment", mission_id: mission_id)

    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the deploying phase (stale retry)
    unless mission['current_phase'] == 'deploying'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected deploying", mission_id: mission_id)
      return
    end

    branch_name = mission['branch_name']

    # Request port allocation and deploy via backend
    deploy_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/deploy", {
      branch: branch_name
    })

    if deploy_result['success']
      log_info("Deployment initiated", mission_id: mission_id,
               port: deploy_result.dig('data', 'port'))
    else
      error_msg = deploy_result['error'] || 'Deployment failed'
      log_error("Deployment failed", error: error_msg)
      report_failure(mission_id, error_msg)
    end
  rescue StandardError => e
    log_error("Mission deploy job failed", exception: e, mission_id: params['mission_id'])
    report_failure(params['mission_id'], e.message) if params['mission_id']
    raise
  end

  private

  def report_failure(mission_id, error_message)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end

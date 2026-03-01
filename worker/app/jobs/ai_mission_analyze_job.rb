# frozen_string_literal: true

class AiMissionAnalyzeJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']

    log_info("Starting mission analysis", mission_id: mission_id)

    # Fetch mission details
    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      log_error("Could not fetch mission", mission_id: mission_id)
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the analyzing phase (stale retry)
    unless mission['current_phase'] == 'analyzing'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected analyzing", mission_id: mission_id)
      return
    end

    repository_id = mission['repository_id']

    unless repository_id
      log_error("No repository linked to mission", mission_id: mission_id)
      report_failure(mission_id, "No repository linked to mission")
      return
    end

    # Call the analyze_repo endpoint on the missions controller
    analysis_response = backend_api_post("/api/v1/ai/missions/analyze_repo", {
      mission_id: mission_id,
      repository_id: repository_id
    })

    if analysis_response['success']
      log_info("Mission analysis completed", mission_id: mission_id)

      # Advance the mission phase
      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: analysis_response.dig('data', 'analysis') || {},
        expected_phase: 'analyzing'
      })
    else
      error_msg = analysis_response['error'] || 'Analysis failed'
      log_error("Mission analysis failed", error: error_msg)
      report_failure(mission_id, error_msg)
    end
  rescue StandardError => e
    log_error("Mission analyze job failed", exception: e, mission_id: params['mission_id'])
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

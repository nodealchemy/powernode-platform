# frozen_string_literal: true

class AiMissionReviewJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission code review", mission_id: mission_id)

    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the reviewing phase (stale retry)
    unless mission['current_phase'] == 'reviewing'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected reviewing", mission_id: mission_id)
      return
    end

    branch_name = mission['branch_name']
    repository_id = mission['repository_id']
    risk_contract_id = mission['risk_contract_id']

    # Trigger Code Factory preflight/review
    review_result = backend_api_post("/api/v1/ai/code_factory/preflight", {
      repository_id: repository_id,
      head_sha: branch_name,
      changed_files: [],
      contract_id: risk_contract_id
    })

    result_data = {
      preflight_passed: review_result.dig('data', 'preflight', 'passed'),
      risk_tier: review_result.dig('data', 'preflight', 'risk_tier'),
      review_state_id: review_result.dig('data', 'preflight', 'review_state_id')
    }

    # Update mission with review state
    if result_data[:review_state_id]
      backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
        mission: { review_state_id: result_data[:review_state_id], review_result: result_data }
      })
    end

    log_info("Code review completed", mission_id: mission_id, passed: result_data[:preflight_passed])

    backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
      result: result_data,
      expected_phase: 'reviewing'
    })
  rescue StandardError => e
    log_error("Mission review job failed", exception: e, mission_id: params['mission_id'])
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

# frozen_string_literal: true

class AiMissionTestJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission testing", mission_id: mission_id)

    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the testing phase (stale retry)
    unless mission['current_phase'] == 'testing'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected testing", mission_id: mission_id)
      return
    end

    branch_name = mission['branch_name']

    unless branch_name
      log_warn("No branch name, skipping tests", mission_id: mission_id)
      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: { tests_skipped: true, reason: "No branch configured" },
        expected_phase: 'testing'
      })
      return
    end

    # Dispatch test workflow via the backend
    test_result = backend_api_post("/api/v1/ai/missions/#{mission_id}/run_tests", {
      branch: branch_name
    })

    if test_result['success']
      log_info("Tests dispatched for mission", mission_id: mission_id)

      # Wait for test results (poll for up to 15 minutes)
      poll_for_test_results(mission_id, test_result.dig('data', 'run_id'))
    else
      error_msg = test_result['error'] || 'Test dispatch failed'
      log_error("Test dispatch failed", error: error_msg)
      report_failure(mission_id, error_msg)
    end
  rescue StandardError => e
    log_error("Mission test job failed", exception: e, mission_id: params['mission_id'])
    report_failure(params['mission_id'], e.message) if params['mission_id']
    raise
  end

  private

  def poll_for_test_results(mission_id, run_id)
    return advance_with_skip(mission_id) unless run_id

    90.times do
      sleep(10)

      status_response = backend_api_get("/api/v1/ai/missions/#{mission_id}/test_status")
      next unless status_response['success']

      test_data = status_response.dig('data', 'test_result') || {}
      status = test_data['status']

      if status == 'completed'
        log_info("Tests completed", mission_id: mission_id, passed: test_data['passed'])
        backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
          result: test_data,
          expected_phase: 'testing'
        })
        return
      elsif status == 'failed'
        log_error("Tests failed", mission_id: mission_id)
        backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
          result: test_data,
          expected_phase: 'testing'
        })
        return
      end
    end

    log_warn("Test polling timed out", mission_id: mission_id)
    advance_with_skip(mission_id)
  end

  def advance_with_skip(mission_id)
    backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
      result: { tests_skipped: true, reason: "Timed out or no run ID" },
      expected_phase: 'testing'
    })
  end

  def report_failure(mission_id, error_message)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end

# frozen_string_literal: true

class AiMissionExecuteJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    log_info("Starting mission execution", mission_id: mission_id)

    # Fetch mission to get ralph_loop_id
    mission_response = backend_api_get("/api/v1/ai/missions/#{mission_id}")
    unless mission_response['success']
      report_failure(mission_id, "Could not fetch mission details")
      return
    end

    mission = mission_response.dig('data', 'mission')

    # Guard: abort if mission has moved past the executing phase (stale retry)
    unless mission['current_phase'] == 'executing'
      log_warn("Stale job: mission phase is #{mission['current_phase']}, expected executing", mission_id: mission_id)
      return
    end

    ralph_loop_id = mission['ralph_loop_id']

    unless ralph_loop_id
      log_warn("No Ralph Loop linked to mission, advancing with stub execution", mission_id: mission_id)
      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: { execution_skipped: true, reason: "No Ralph Loop configured — stub execution" },
        expected_phase: 'executing'
      })
      return
    end

    # Start the Ralph Loop
    start_result = backend_api_post("/api/v1/ai/ralph_loops/#{ralph_loop_id}/start", {})
    unless start_result['success']
      log_error("Failed to start Ralph Loop", ralph_loop_id: ralph_loop_id)
      report_failure(mission_id, "Failed to start execution: #{start_result['error']}")
      return
    end

    log_info("Ralph Loop started for mission", mission_id: mission_id, ralph_loop_id: ralph_loop_id)

    # Poll for completion (max 30 minutes)
    max_polls = 180
    poll_interval = 10

    max_polls.times do |i|
      sleep(poll_interval)

      loop_response = backend_api_get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
      next unless loop_response['success']

      loop_data = loop_response.dig('data', 'ralph_loop')
      loop_status = loop_data['status']

      if %w[completed].include?(loop_status)
        log_info("Execution completed", mission_id: mission_id, ralph_loop_id: ralph_loop_id)
        backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
          result: { ralph_loop_status: loop_status, completed_tasks: loop_data['completed_tasks'] },
          expected_phase: 'executing'
        })
        return
      elsif %w[failed cancelled].include?(loop_status)
        log_error("Execution failed", mission_id: mission_id, status: loop_status)
        report_failure(mission_id, "Execution #{loop_status}")
        return
      end

      # Log progress periodically
      if (i + 1) % 6 == 0
        log_info("Execution in progress", mission_id: mission_id, poll: i + 1,
                 status: loop_status, completed: loop_data['completed_tasks'], total: loop_data['total_tasks'])
      end
    end

    log_error("Execution timed out", mission_id: mission_id)
    report_failure(mission_id, "Execution timed out after 30 minutes")
  rescue StandardError => e
    log_error("Mission execute job failed", exception: e, mission_id: params['mission_id'])
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

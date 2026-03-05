# frozen_string_literal: true

class AiMissionExecuteJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  MAX_POLLS = 180
  BASE_DELAY = 10
  MAX_DELAY = 30

  def execute(params)
    validate_required_params(params, 'mission_id', 'account_id')

    mission_id = params['mission_id']
    poll_count = params['poll_count'].to_i

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

    # First invocation: start the loop and trigger run_all
    if poll_count == 0
      log_info("Starting mission execution", mission_id: mission_id, ralph_loop_id: ralph_loop_id)
      unless start_ralph_loop(mission_id, ralph_loop_id)
        return
      end
    end

    # Check loop status
    loop_response = backend_api_get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
    unless loop_response['success']
      log_warn("Could not fetch loop status", ralph_loop_id: ralph_loop_id, poll: poll_count)
      schedule_next_poll(params, poll_count)
      return
    end

    loop_data = loop_response.dig('data', 'ralph_loop')
    loop_status = loop_data['status']

    case loop_status
    when 'completed'
      log_info("Execution completed", mission_id: mission_id, ralph_loop_id: ralph_loop_id)
      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: { ralph_loop_status: 'completed', completed_tasks: loop_data['completed_tasks'] },
        expected_phase: 'executing'
      })
    when 'failed', 'cancelled'
      log_error("Execution failed", mission_id: mission_id, status: loop_status)
      report_failure(mission_id, "Execution #{loop_status}")
    else
      # Still running — check if all tasks are actually done (run_all may have
      # exited without transitioning the loop status)
      completed_tasks = loop_data['completed_tasks'].to_i
      total_tasks = loop_data['total_tasks'].to_i
      if total_tasks > 0 && completed_tasks >= total_tasks
        log_warn("Loop stuck: all tasks done but status=#{loop_status}, triggering run_iteration to complete",
                 mission_id: mission_id, ralph_loop_id: ralph_loop_id)
        backend_api_post("/api/v1/internal/ai/ralph_loops/#{ralph_loop_id}/run_iteration", {})
        schedule_next_poll(params, poll_count)
        return
      end

      # Re-enqueue with incremented poll count
      if poll_count >= MAX_POLLS
        log_error("Execution timed out", mission_id: mission_id)
        report_failure(mission_id, "Execution timed out after #{MAX_POLLS} polls")
        return
      end

      # Log progress periodically
      if (poll_count + 1) % 6 == 0
        log_info("Execution in progress", mission_id: mission_id, poll: poll_count + 1,
                 status: loop_status, completed: loop_data['completed_tasks'], total: loop_data['total_tasks'])
      end

      schedule_next_poll(params, poll_count)
    end
  rescue StandardError => e
    log_error("Mission execute job failed", exception: e, mission_id: params['mission_id'])
    report_failure(params['mission_id'], e.message) if params['mission_id']
    raise
  end

  private

  def start_ralph_loop(mission_id, ralph_loop_id)
    # Check loop status before attempting start
    loop_check = backend_api_get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
    loop_status = loop_check.dig('data', 'ralph_loop', 'status')

    if loop_status == 'completed'
      log_info("Ralph Loop already completed, advancing mission", mission_id: mission_id, ralph_loop_id: ralph_loop_id)
      loop_data = loop_check.dig('data', 'ralph_loop')
      backend_api_post("/api/v1/ai/missions/#{mission_id}/advance", {
        result: { ralph_loop_status: 'completed', completed_tasks: loop_data['completed_tasks'] },
        expected_phase: 'executing'
      })
      return false
    elsif %w[failed cancelled].include?(loop_status)
      log_error("Ralph Loop already in terminal state", mission_id: mission_id, status: loop_status)
      report_failure(mission_id, "Execution #{loop_status}")
      return false
    elsif loop_status == 'running'
      log_info("Ralph Loop already running, skipping start", ralph_loop_id: ralph_loop_id)
      return true
    end

    # Start the Ralph Loop (status should be 'pending')
    start_result = backend_api_post("/api/v1/ai/ralph_loops/#{ralph_loop_id}/start", {})
    unless start_result['success']
      log_error("Failed to start Ralph Loop", ralph_loop_id: ralph_loop_id)
      report_failure(mission_id, "Failed to start execution: #{start_result['error']}")
      return false
    end
    log_info("Ralph Loop started for mission", mission_id: mission_id, ralph_loop_id: ralph_loop_id)

    # Trigger run_all to execute tasks (start_loop only transitions state)
    run_result = backend_api_post("/api/v1/ai/ralph_loops/#{ralph_loop_id}/run_all", {
      stop_on_error: false
    })
    unless run_result['success']
      log_warn("run_all failed, tasks may need manual trigger", error: run_result['error'])
    end

    true
  end

  def schedule_next_poll(params, current_poll)
    delay = [BASE_DELAY * (1.1**current_poll), MAX_DELAY].min.to_i
    self.class.perform_in(
      delay,
      params.merge('poll_count' => current_poll + 1)
    )
  end

  def report_failure(mission_id, error_message)
    backend_api_patch("/api/v1/ai/missions/#{mission_id}", {
      mission: { status: "failed", error_message: error_message }
    })
  rescue StandardError => e
    log_warn("Failed to report mission failure", error: e.message)
  end
end

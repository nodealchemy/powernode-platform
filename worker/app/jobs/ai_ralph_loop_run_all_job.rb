# frozen_string_literal: true

class AiRalphLoopRunAllJob < BaseJob
  include AiJobsConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: 'ai_execution', retry: 0

  MAX_DURATION = 3600 # 1 hour

  def execute(ralph_loop_id, options = {})
    options = options.is_a?(String) ? JSON.parse(options) : options
    stop_on_error = options['stop_on_error'] || false

    log_info("[RalphLoopRunAll] Starting all iterations", ralph_loop_id: ralph_loop_id)

    start_time = Time.current
    iteration = 0

    # Kill switch check — resolve the owning account from the loop record and
    # bail if AI activity is suspended before running any iteration.
    loop_record = api_client.get("/api/v1/ai/ralph_loops/#{ralph_loop_id}")
    account_id = loop_record.dig('data', 'ralph_loop', 'account_id')
    return if bail_if_ai_suspended!(account_id)

    loop do
      # Check timeout
      if Time.current - start_time > MAX_DURATION
        log_info("[RalphLoopRunAll] Timeout reached after #{iteration} iterations")
        break
      end

      # Execute next iteration via server API
      response = api_client.post("/api/v1/internal/ai/ralph_loops/#{ralph_loop_id}/run_iteration", {
        iteration: iteration
      })

      # Check for completion/cancellation in both success and error responses
      if response.dig('data', 'completed')
        log_info("[RalphLoopRunAll] All iterations completed after #{iteration} iterations")
        break
      end

      if response.dig('data', 'cancelled')
        log_info("[RalphLoopRunAll] Loop cancelled after #{iteration} iterations")
        break
      end

      unless response['success']
        if stop_on_error
          log_error("[RalphLoopRunAll] Iteration #{iteration} failed, stopping: #{response['error']}")
          break
        end

        log_error("[RalphLoopRunAll] Iteration #{iteration} failed, continuing: #{response['error']}")
      end

      iteration += 1
      sleep(2) # Brief pause between iterations
    end

    log_info("[RalphLoopRunAll] Completed", iterations: iteration,
      duration_seconds: (Time.current - start_time).round)
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("[RalphLoopRunAll] Backend unavailable, stopping after #{iteration} iterations",
      ralph_loop_id: ralph_loop_id)
  rescue BackendApiClient::ApiError => e
    log_info("[RalphLoopRunAll] Stopped: #{e.message}", ralph_loop_id: ralph_loop_id)
  end
end

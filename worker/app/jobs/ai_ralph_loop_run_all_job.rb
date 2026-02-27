# frozen_string_literal: true

class AiRalphLoopRunAllJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 0

  MAX_DURATION = 3600 # 1 hour

  def execute(ralph_loop_id, options = {})
    options = options.is_a?(String) ? JSON.parse(options) : options
    stop_on_error = options['stop_on_error'] || false

    log_info("[RalphLoopRunAll] Starting all iterations", ralph_loop_id: ralph_loop_id)

    start_time = Time.current
    iteration = 0

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

      unless response['success']
        if response.dig('data', 'completed')
          log_info("[RalphLoopRunAll] All iterations completed after #{iteration} iterations")
          break
        end

        if response.dig('data', 'cancelled')
          log_info("[RalphLoopRunAll] Loop cancelled after #{iteration} iterations")
          break
        end

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
  end
end

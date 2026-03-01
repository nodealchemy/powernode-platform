# frozen_string_literal: true

# Worker-side job for AI team execution.
# Delegates strategy execution to the server's internal team strategy endpoint,
# which handles all coordination patterns (sequential, parallel, hierarchical, mesh).
class AiTeamExecutionJob < BaseJob
  include AiJobsConcern
  include AiLlmProxyConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(params)
    params = params.is_a?(String) ? JSON.parse(params) : params
    params = params.transform_keys(&:to_s)

    team_id = params['team_id']
    user_id = params['user_id']
    input = params['input'] || {}
    context = params['context'] || {}

    validate_required_params(params, 'team_id')

    log_info("Starting AI team execution", team_id: team_id, user_id: user_id)

    # Kill switch check
    return if bail_if_ai_suspended!(params['account_id'])

    # Create execution via server API
    execution = create_execution(team_id, user_id, input, context)
    return unless execution

    execution_id = execution['id']
    log_info("Team execution created", execution_id: execution_id)

    begin
      # Delegate strategy execution to server
      result = backend_api_post("/api/v1/internal/ai/teams/#{team_id}/execute_strategy", {
        execution_id: execution_id,
        input: input,
        context: context
      })

      if result['success']
        log_info("Team execution completed",
          execution_id: execution_id,
          tasks_completed: result.dig('data', 'tasks_completed'),
          total_cost: result.dig('data', 'total_cost')
        )
      else
        error_msg = result['error'] || 'Strategy execution failed'
        fail_execution(execution_id, error_msg)
        log_error("Team execution failed", execution_id: execution_id, error: error_msg)
      end
    rescue StandardError => e
      fail_execution(execution_id, e.message)
      raise
    end
  end

  private

  def create_execution(team_id, user_id, input, context)
    response = backend_api_post("/api/v1/ai/teams/#{team_id}/executions", {
      objective: input['task'] || input['prompt'],
      input_context: input
    })

    if response['success']
      response['data']['team_execution'] || response['data']
    else
      log_error("Failed to create team execution", team_id: team_id, error: response['error'])
      nil
    end
  rescue StandardError => e
    log_error("Error creating team execution", e, team_id: team_id)
    nil
  end

  def fail_execution(execution_id, error_message)
    backend_api_post("/api/v1/ai/teams/executions/#{execution_id}/cancel", {
      reason: error_message.to_s.truncate(500)
    })
  rescue StandardError => e
    log_error("Failed to mark execution as failed", e, execution_id: execution_id)
  end
end

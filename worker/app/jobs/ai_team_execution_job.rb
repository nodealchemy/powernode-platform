# frozen_string_literal: true

# Worker-side job for AI team execution
# Delegates to the server's /api/v1/ai/agent_teams/:id/execute endpoint
# and polls for completion status.
#
# This job is the worker counterpart to server's Ai::AgentTeamExecutionJob.
# It orchestrates team execution via HTTP API calls to the server backend.
class AiTeamExecutionJob < BaseJob
  include AiJobsConcern
  include AiProviderCallsConcern
  include AiPromptBuildingConcern
  include AiGenericProviderConcern
  include AiCostCalculationConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  # Maximum time to wait for team execution to complete
  MAX_POLL_DURATION = 1800 # 30 minutes
  POLL_INTERVAL = 10 # seconds between status checks

  def execute(params)
    params = params.is_a?(String) ? JSON.parse(params) : params
    params = params.transform_keys(&:to_s)

    team_id = params['team_id']
    user_id = params['user_id']
    input = params['input'] || {}
    context = params['context'] || {}

    validate_required_params(params, 'team_id', 'user_id')

    log_info("Starting AI team execution",
      team_id: team_id,
      user_id: user_id,
      task_type: input['task_type']
    )

    # Fetch team details
    team = fetch_team(team_id)
    return unless team

    # Create execution via server API
    execution = create_execution(team_id, user_id, input, context)
    return unless execution

    execution_id = execution['id']
    log_info("Team execution created",
      execution_id: execution_id,
      team_name: team['name']
    )

    # Execute team members based on coordination strategy
    begin
      strategy = team.dig('team_config', 'coordination_strategy') || team['coordination_strategy'] || 'manager_led'
      members = fetch_team_members(team_id)

      if members.blank?
        fail_execution(execution_id, "No team members found")
        return
      end

      log_info("Executing team with strategy",
        strategy: strategy,
        member_count: members.length
      )

      results = execute_team_members(execution_id, team, members, input, strategy)

      # Complete execution
      complete_execution(execution_id, results)

      log_info("Team execution completed",
        execution_id: execution_id,
        tasks_completed: results[:tasks_completed],
        tasks_failed: results[:tasks_failed],
        total_cost: results[:total_cost]
      )
    rescue StandardError => e
      fail_execution(execution_id, e.message)
      raise
    end
  end

  private

  def fetch_team(team_id)
    response = backend_api_get("/api/v1/ai/agent_teams/#{team_id}")

    if response['success']
      response['data']['agent_team'] || response['data']
    else
      log_error("Failed to fetch team", team_id: team_id)
      nil
    end
  rescue StandardError => e
    log_error("Error fetching team", e, team_id: team_id)
    nil
  end

  def fetch_team_members(team_id)
    response = backend_api_get("/api/v1/ai/agent_teams/#{team_id}/members")

    if response['success']
      response['data']['members'] || response['data']
    else
      log_error("Failed to fetch team members", team_id: team_id)
      []
    end
  rescue StandardError => e
    log_error("Error fetching team members", e, team_id: team_id)
    []
  end

  def create_execution(team_id, user_id, input, context)
    response = backend_api_post("/api/v1/ai/team_executions", {
      team_execution: {
        agent_team_id: team_id,
        triggered_by_id: user_id,
        input_context: input,
        objective: input['task'] || input['prompt'],
        status: 'running'
      }
    })

    if response['success']
      response['data']['team_execution'] || response['data']
    else
      log_error("Failed to create team execution",
        team_id: team_id,
        error: response['error']
      )
      nil
    end
  rescue StandardError => e
    log_error("Error creating team execution", e, team_id: team_id)
    nil
  end

  def execute_team_members(execution_id, team, members, input, strategy)
    results = {
      tasks_completed: 0,
      tasks_failed: 0,
      total_cost: 0.0,
      total_tokens: 0,
      outputs: []
    }

    # Sort members by role priority
    sorted_members = sort_by_role(members)
    skip_on_failure = team.dig('team_config', 'skip_on_member_failure') != false

    sorted_members.each do |member|
      agent = member['agent'] || member['ai_agent']
      next unless agent

      role = member['role'] || 'executor'
      agent_name = agent['name']

      log_info("Executing team member",
        execution_id: execution_id,
        agent_name: agent_name,
        role: role
      )

      begin
        # Build agent-specific prompt
        agent_input = build_team_member_input(agent, role, input, results[:outputs])

        # Execute agent via provider
        result = execute_single_agent(agent, agent_input)

        if result[:success]
          results[:tasks_completed] += 1
          results[:total_cost] += result[:cost] || 0.0
          results[:total_tokens] += result[:tokens_used] || 0
          results[:outputs] << {
            agent_id: agent['id'],
            agent_name: agent_name,
            role: role,
            output: result[:response],
            cost: result[:cost],
            tokens_used: result[:tokens_used]
          }

          # Report progress
          update_execution_progress(execution_id, results)
        else
          results[:tasks_failed] += 1
          log_error("Agent execution failed",
            agent_name: agent_name,
            error: result[:error]
          )

          unless skip_on_failure
            raise "Agent #{agent_name} failed: #{result[:error]}"
          end
        end
      rescue StandardError => e
        results[:tasks_failed] += 1
        log_error("Agent execution error", e,
          agent_name: agent_name,
          role: role
        )
        raise unless skip_on_failure
      end
    end

    results
  end

  def execute_single_agent(agent, input)
    provider_id = agent['ai_provider_id'] || agent.dig('provider', 'id')
    return { success: false, error: 'No provider configured' } unless provider_id

    # Fetch provider and credentials
    provider_response = backend_api_get("/api/v1/ai/providers/#{provider_id}")
    return { success: false, error: 'Failed to fetch provider' } unless provider_response['success']

    provider = provider_response['data']['provider'] || provider_response['data']

    credentials_response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider_id,
      default_only: true,
      active: true
    })

    unless credentials_response['success']
      return { success: false, error: 'Failed to fetch credentials' }
    end

    credentials = (credentials_response['data']['credentials'] || []).first
    return { success: false, error: 'No active credentials found' } unless credentials

    # Build prompt
    system_prompt = agent['system_prompt'] || ''
    model = agent.dig('configuration', 'model') || agent['model'] || 'gpt-4o'

    prompt = "#{system_prompt}\n\n## Task\n#{input[:task]}"
    if input[:previous_outputs].present?
      prompt += "\n\n## Context from Previous Team Members\n#{input[:previous_outputs]}"
    end

    # Call AI provider
    start_time = Time.current
    ai_response = call_ai_provider(provider, credentials, prompt, nil)
    duration_ms = ((Time.current - start_time) * 1000).to_i

    if ai_response[:success]
      {
        success: true,
        response: ai_response[:response],
        cost: ai_response[:cost] || 0.0,
        tokens_used: ai_response.dig(:metadata, :tokens_used) || 0,
        model_used: model,
        duration_ms: duration_ms
      }
    else
      {
        success: false,
        error: ai_response[:error] || 'Provider call failed',
        duration_ms: duration_ms
      }
    end
  end

  def build_team_member_input(agent, role, input, previous_outputs)
    result = {
      task: input['task'] || input['prompt'] || '',
      role: role,
      task_type: input['task_type']
    }

    if previous_outputs.present?
      summary = previous_outputs.map { |o|
        "### #{o[:agent_name]} (#{o[:role]})\n#{o[:output]&.truncate(2000)}"
      }.join("\n\n")
      result[:previous_outputs] = summary
    end

    result
  end

  def sort_by_role(members)
    role_order = { 'manager' => 0, 'coordinator' => 1, 'executor' => 2, 'reviewer' => 3, 'facilitator' => 4 }
    members.sort_by { |m| role_order[m['role']] || 5 }
  end

  def update_execution_progress(execution_id, results)
    backend_api_patch("/api/v1/ai/team_executions/#{execution_id}", {
      team_execution: {
        tasks_completed: results[:tasks_completed],
        tasks_failed: results[:tasks_failed],
        total_cost_usd: results[:total_cost],
        total_tokens_used: results[:total_tokens]
      }
    })
  rescue StandardError => e
    log_warn("Failed to update execution progress: #{e.message}")
  end

  def complete_execution(execution_id, results)
    # Build output summary from last executor
    last_output = results[:outputs].last
    output_result = if last_output
      {
        response: last_output[:output],
        agent_name: last_output[:agent_name],
        role: last_output[:role],
        cost_usd: results[:total_cost].to_s,
        tokens_used: results[:total_tokens]
      }
    else
      { response: 'No output generated', cost_usd: '0.0', tokens_used: 0 }
    end

    backend_api_patch("/api/v1/ai/team_executions/#{execution_id}", {
      team_execution: {
        status: 'completed',
        tasks_completed: results[:tasks_completed],
        tasks_failed: results[:tasks_failed],
        tasks_total: results[:tasks_completed] + results[:tasks_failed],
        total_cost_usd: results[:total_cost],
        total_tokens_used: results[:total_tokens],
        output_result: output_result,
        completed_at: Time.current.iso8601,
        termination_reason: 'completed'
      }
    })
  rescue StandardError => e
    log_error("Failed to complete execution", e, execution_id: execution_id)
  end

  def fail_execution(execution_id, error_message)
    backend_api_patch("/api/v1/ai/team_executions/#{execution_id}", {
      team_execution: {
        status: 'failed',
        termination_reason: error_message.truncate(500),
        completed_at: Time.current.iso8601
      }
    })
  rescue StandardError => e
    log_error("Failed to mark execution as failed", e, execution_id: execution_id)
  end

  def call_ai_provider(provider, credentials, prompt, context)
    provider_type = provider['provider_type']&.downcase || 'custom'

    enhanced_context = add_provider_standardization_context(context, provider_type)

    case provider_type
    when 'openai'
      call_openai_provider(credentials, prompt, enhanced_context)
    when 'anthropic'
      call_anthropic_provider(credentials, prompt, enhanced_context)
    when 'ollama', 'custom'
      if ollama_compatible_provider?(provider, credentials)
        call_ollama_provider(credentials, prompt, enhanced_context)
      else
        call_generic_provider(provider, credentials, prompt, enhanced_context)
      end
    else
      call_generic_provider(provider, credentials, prompt, enhanced_context)
    end
  end
end

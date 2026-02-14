# frozen_string_literal: true

class AiAgentExecutionJob < BaseJob
  include AiJobsConcern
  include AiProviderCallsConcern
  include AiPromptBuildingConcern
  include AiGenericProviderConcern
  include AiCostCalculationConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  def execute(agent_execution_id)
    validate_required_params({ 'agent_execution_id' => agent_execution_id }, 'agent_execution_id')

    log_info("Starting AI agent execution", agent_execution_id: agent_execution_id)

    # Fetch the AI agent execution from backend
    @agent_execution = fetch_agent_execution(agent_execution_id)
    return unless @agent_execution

    # Validate execution state
    unless can_execute_agent?
      log_error("Cannot execute agent - invalid state", status: @agent_execution['status'])
      return
    end

    begin
      # Update status to running
      update_execution_status('running')

      # Execute the AI agent
      result = execute_ai_agent_with_multi_turn

      if result[:success]
        # Update with success
        complete_agent_execution(result)
        log_info("AI agent execution completed successfully",
          agent_execution_id: agent_execution_id,
          duration_ms: result[:duration_ms],
          cost: result[:cost],
          turns: result[:conversation_turns] || 1
        )
      else
        # Update with failure
        fail_agent_execution(result[:error])
        log_error("AI agent execution failed",
          agent_execution_id: agent_execution_id,
          error: result[:error]
        )
      end

    rescue StandardError => e
      fail_agent_execution(e.message)
      handle_ai_processing_error(e, { agent_execution_id: agent_execution_id })
    end
  end

  private

  def fetch_agent_execution(agent_execution_id)
    response = backend_api_get("/api/v1/ai/executions/#{agent_execution_id}")

    if response['success']
      response['data']['agent_execution']
    else
      log_error("Failed to fetch agent execution", agent_execution_id: agent_execution_id)
      nil
    end
  end

  def can_execute_agent?
    return false unless @agent_execution

    # Check if execution is in pending state
    status = @agent_execution['status']
    valid_statuses = %w[pending queued]

    unless valid_statuses.include?(status)
      log_warn("Agent execution not in executable state",
        status: status,
        valid_statuses: valid_statuses
      )
      return false
    end

    # Validate required data
    unless @agent_execution['ai_agent']
      log_error("Agent execution missing agent data")
      return false
    end

    unless @agent_execution['ai_provider']
      log_error("Agent execution missing provider data")
      return false
    end

    true
  end

  def update_execution_status(status, additional_data = {})
    payload = {
      agent_execution: {
        status: status,
        **additional_data
      }
    }

    backend_api_patch("/api/v1/ai/executions/#{@agent_execution['id']}", payload)
  end

  def execute_ai_agent
    start_time = Time.current

    agent = @agent_execution['ai_agent']
    provider = @agent_execution['ai_provider']
    input_data = @agent_execution['input_parameters'] || {}

    log_info("Executing AI agent",
      agent_name: agent['name'],
      provider_name: provider['name'],
      input_keys: input_data.keys
    )

    # Get provider credentials
    credentials_response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider['id'],
      default_only: true,
      active: true
    })

    unless credentials_response['success']
      return { success: false, error: 'Failed to fetch provider credentials' }
    end

    credentials = credentials_response['data']['credentials'].first
    unless credentials
      return { success: false, error: 'No active credentials found for provider' }
    end

    # Prepare prompt and context
    prompt_text = build_agent_prompt(agent, input_data)
    context = build_agent_context(input_data)

    # Call AI provider
    ai_response = call_ai_provider(provider, credentials, prompt_text, context)

    execution_time = Time.current - start_time
    duration_ms = (execution_time * 1000).to_i

    if ai_response[:success]
      {
        success: true,
        response_data: {
          content: ai_response[:response],
          metadata: ai_response[:metadata]
        },
        output_data: extract_output_data(ai_response),
        duration_ms: duration_ms,
        cost: ai_response[:cost] || 0.0,
        model_used: ai_response[:model],
        tokens_used: ai_response.dig(:metadata, :tokens_used) || 0
      }
    else
      {
        success: false,
        error: ai_response[:error] || 'Unknown AI provider error',
        duration_ms: duration_ms
      }
    end
  end

  def execute_ai_agent_with_multi_turn
    start_time = Time.current
    agent = @agent_execution['ai_agent']

    # Check if multi-turn is enabled for this agent
    multi_turn_config = agent.dig('configuration', 'multi_turn') || {}
    max_turns = multi_turn_config['max_turns'] || 3
    enable_multi_turn = multi_turn_config['enabled'] != false

    log_info("Starting AI agent execution",
      multi_turn_enabled: enable_multi_turn,
      max_turns: max_turns
    )

    conversation_history = []
    conversation_turns = 0
    total_cost = 0.0
    total_tokens = 0
    combined_response = ""

    begin
      loop do
        conversation_turns += 1

        # Execute single turn
        turn_result = execute_ai_agent_turn(conversation_history, conversation_turns)

        unless turn_result[:success]
          return {
            success: false,
            error: turn_result[:error],
            duration_ms: ((Time.current - start_time) * 1000).to_i,
            conversation_turns: conversation_turns
          }
        end

        # Accumulate metrics
        total_cost += turn_result[:cost] || 0.0
        total_tokens += turn_result[:tokens_used] || 0

        # Add to conversation history
        conversation_history << {
          turn: conversation_turns,
          prompt: turn_result[:prompt_used],
          response: turn_result[:response_data][:content],
          timestamp: Time.current.iso8601
        }

        current_response = turn_result[:response_data][:content]

        # Check if multi-turn is enabled and if we should continue
        if enable_multi_turn && conversation_turns < max_turns
          follow_up_needed = analyze_response_for_follow_up(current_response, agent)

          if follow_up_needed[:needs_follow_up]
            log_info("Multi-turn follow-up needed",
              turn: conversation_turns,
              reason: follow_up_needed[:reason],
              next_turn: conversation_turns + 1
            )

            # Continue to next turn
            combined_response = current_response
            next
          end
        end

        # Response is satisfactory or max turns reached
        combined_response = current_response
        break
      end

      execution_time = Time.current - start_time
      duration_ms = (execution_time * 1000).to_i

      log_info("Multi-turn AI agent execution completed",
        turns: conversation_turns,
        total_cost: total_cost,
        duration_ms: duration_ms
      )

      {
        success: true,
        response_data: {
          content: combined_response,
          metadata: {
            conversation_turns: conversation_turns,
            conversation_history: conversation_history,
            multi_turn_enabled: enable_multi_turn
          }
        },
        output_data: extract_output_data({ response: combined_response, metadata: { tokens_used: total_tokens } }),
        duration_ms: duration_ms,
        cost: total_cost,
        model_used: agent['configuration']&.dig('model') || 'unknown',
        tokens_used: total_tokens,
        conversation_turns: conversation_turns
      }

    rescue StandardError => e
      log_error("Multi-turn execution failed", error: e.message)
      {
        success: false,
        error: "Multi-turn execution failed: #{e.message}",
        duration_ms: ((Time.current - start_time) * 1000).to_i,
        conversation_turns: conversation_turns
      }
    end
  end

  def execute_ai_agent_turn(conversation_history, turn_number)
    agent = @agent_execution['ai_agent']
    provider = @agent_execution['ai_provider']
    input_data = @agent_execution['input_parameters'] || {}

    log_info("Executing AI agent turn",
      turn: turn_number,
      agent_name: agent['name'],
      provider_name: provider['name']
    )

    # Get provider credentials
    credentials_response = backend_api_get("/api/v1/ai/credentials", {
      provider_id: provider['id'],
      default_only: true,
      active: true
    })

    unless credentials_response['success']
      return { success: false, error: 'Failed to fetch provider credentials' }
    end

    credentials = credentials_response['data']['credentials'].first
    unless credentials
      return { success: false, error: 'No active credentials found for provider' }
    end

    # Build prompt with conversation context
    prompt_text = build_multi_turn_prompt(agent, input_data, conversation_history, turn_number)

    # Prepare AI service configuration
    ai_config = build_ai_service_config(agent, provider, credentials)
    ai_config[:prompt] = prompt_text

    # Call AI provider
    ai_response = call_ai_provider(ai_config)

    if ai_response[:success]
      {
        success: true,
        response_data: {
          content: ai_response[:response],
          metadata: ai_response[:metadata]
        },
        output_data: extract_output_data(ai_response),
        cost: ai_response[:cost] || 0.0,
        model_used: ai_response[:model],
        tokens_used: ai_response.dig(:metadata, :tokens_used) || 0,
        prompt_used: prompt_text
      }
    else
      {
        success: false,
        error: ai_response[:error] || 'Unknown AI provider error'
      }
    end
  end

  # Multi-turn call_ai_provider method (single config parameter)
  def call_ai_provider(config_or_provider, credentials = nil, prompt = nil, context = nil)
    if config_or_provider.is_a?(Hash) && credentials.nil?
      # Multi-turn execution - single config hash parameter
      call_ai_provider_with_config(config_or_provider)
    else
      # Original execution - individual parameters
      call_ai_provider_with_params(config_or_provider, credentials, prompt, context)
    end
  end

  def call_ai_provider_with_config(ai_config)
    provider = ai_config[:provider]
    credentials = ai_config[:credentials]
    prompt = ai_config[:prompt]
    context = ai_config[:context]

    call_ai_provider_with_params(provider, credentials, prompt, context)
  end

  def call_ai_provider_with_params(provider, credentials, prompt, context)
    provider_type = provider['provider_type']&.downcase || 'custom'

    # Add provider-specific standardization instructions to context
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

  def complete_agent_execution(result)
    payload = {
      agent_execution: {
        status: 'completed',
        output_data: result[:output_data],
        cost_usd: result[:cost],
        duration_ms: result[:duration_ms],
        tokens_used: result[:tokens_used],
        completed_at: Time.current.iso8601
      }
    }

    backend_api_patch("/api/v1/ai/executions/#{@agent_execution['id']}", payload)
  end

  def fail_agent_execution(error_message)
    payload = {
      agent_execution: {
        status: 'failed',
        error_message: error_message,
        completed_at: Time.current.iso8601
      }
    }

    backend_api_patch("/api/v1/ai/executions/#{@agent_execution['id']}", payload)
  end
end

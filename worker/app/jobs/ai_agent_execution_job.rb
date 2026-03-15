# frozen_string_literal: true

# Worker-side AI agent execution job.
# Delegates all LLM calls, tool-calling, memory injection, and governance checks
# to the server via the internal LLM proxy API.
class AiAgentExecutionJob < BaseJob
  include AiJobsConcern
  include AiLlmProxyConcern
  include AiCostCalculationConcern
  include AiSuspensionCheckConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  def execute(agent_execution_id)
    validate_required_params({ 'agent_execution_id' => agent_execution_id }, 'agent_execution_id')

    log_info("Starting AI agent execution", agent_execution_id: agent_execution_id)

    @agent_execution = fetch_agent_execution(agent_execution_id)
    return unless @agent_execution

    # Kill switch check — bail if AI activity is suspended
    return if bail_if_ai_suspended!(@agent_execution['account_id'])

    unless can_execute_agent?
      log_error("Cannot execute agent - invalid state", status: @agent_execution['status'])
      return
    end

    # Budget pre-check
    budget_check = check_budget_gate
    if budget_check && !budget_check[:allowed]
      fail_agent_execution("Budget exhausted: #{budget_check[:remaining_cents]} cents remaining")
      log_warn("Agent execution blocked by budget gate", agent_execution_id: agent_execution_id)
      return
    end

    begin
      update_execution_status('running')
      emit_telemetry("agent_execution_started")

      result = execute_via_proxy

      if result[:success]
        complete_agent_execution(result)
        log_info("AI agent execution completed successfully",
          agent_execution_id: agent_execution_id,
          duration_ms: result[:duration_ms],
          cost: result[:cost]
        )
      else
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

  # Core execution: delegates everything to server-side LLM proxy
  def execute_via_proxy
    start_time = Time.current
    agent = @agent_execution['ai_agent']
    agent_id = agent['id']
    input_data = @agent_execution['input_parameters'] || {}
    input_data = { "input" => input_data } if input_data.is_a?(String)

    log_info("Executing AI agent via LLM proxy",
      agent_name: agent['name'],
      agent_id: agent_id
    )

    # 1. Fetch memory-enriched execution context from server
    ctx = fetch_execution_context(agent_id, {
      input: input_data['input'] || input_data.to_json,
      context: input_data['context'] || {},
      memory_token_budget: input_data.dig('context', 'memory_token_budget') || 4000
    })

    execution_context = ctx['execution_context'] || {}
    system_prompt = ctx['system_prompt']
    model = ctx['model']

    # 2. Build messages from context
    messages = []
    if execution_context['additional_context'].present?
      messages << { role: "user", content: "#{execution_context['input']}\n\nAdditional Context:\n#{execution_context['additional_context']}" }
    else
      messages << { role: "user", content: execution_context['input'].to_s }
    end

    # 3. Determine reasoning mode from agent config
    reasoning_config = agent.dig('mcp_metadata', 'reasoning') || {}
    reasoning_mode = reasoning_config['mode']
    reflection_enabled = reasoning_config['reflection_enabled'] == true

    # 4. Execute via server proxy (WebSocket with HTTP fallback)
    proxy = llm_proxy_with_websocket || llm_proxy

    proxy_result = if reasoning_mode.present?
      proxy.execute_with_reasoning(
        agent_id: agent_id,
        messages: messages,
        model: model,
        system_prompt: system_prompt,
        max_tokens: ctx['max_tokens'] || 2000,
        temperature: ctx['temperature'] || 0.7,
        reasoning_mode: reasoning_mode,
        reflection_enabled: reflection_enabled
      )
    else
      proxy.execute_tool_loop(
        agent_id: agent_id,
        messages: messages,
        model: model,
        system_prompt: system_prompt,
        max_tokens: ctx['max_tokens'] || 2000,
        temperature: ctx['temperature'] || 0.7
      )
    end

    duration_ms = ((Time.current - start_time) * 1000).to_i
    content = proxy_result['content'] || proxy_result[:content]
    usage = proxy_result['usage'] || proxy_result[:usage] || {}
    tokens_used = usage['total_tokens'] || usage[:total_tokens] || 0
    cost = proxy_result['cost'] || proxy_result[:cost] || 0.0

    cleaned_content = clean_ai_response(content.to_s)

    {
      success: true,
      response_data: { content: cleaned_content },
      output_data: {
        'content' => cleaned_content,
        'response' => cleaned_content,
        'model_used' => model,
        'tokens_used' => tokens_used,
        'prompt_tokens' => usage['prompt_tokens'] || usage[:prompt_tokens] || 0,
        'completion_tokens' => usage['completion_tokens'] || usage[:completion_tokens] || 0,
        'cached_tokens' => usage['cached_tokens'] || usage[:cached_tokens] || 0,
        'cost_usd' => cost,
        'tool_calls' => proxy_result['tool_calls_log'] || proxy_result[:tool_calls_log]
      },
      duration_ms: duration_ms,
      cost: cost,
      model_used: model,
      tokens_used: tokens_used
    }
  rescue StandardError => e
    log_error("LLM proxy execution failed", error: e.message)
    { success: false, error: "Proxy execution failed: #{e.message}" }
  ensure
    disconnect_tool_dispatch_ws
  end

  def fetch_agent_execution(agent_execution_id)
    response = backend_api_get("/api/v1/internal/ai/executions/#{agent_execution_id}")

    if response['success']
      response['data']['agent_execution']
    else
      log_error("Failed to fetch agent execution", agent_execution_id: agent_execution_id)
      nil
    end
  end

  def can_execute_agent?
    return false unless @agent_execution

    status = @agent_execution['status']
    valid_statuses = %w[pending queued]

    unless valid_statuses.include?(status)
      log_warn("Agent execution not in executable state", status: status, valid_statuses: valid_statuses)
      return false
    end

    unless @agent_execution['ai_agent']
      log_error("Agent execution missing agent data")
      return false
    end

    true
  end

  def update_execution_status(status, additional_data = {})
    backend_api_patch("/api/v1/internal/ai/executions/#{@agent_execution['id']}", {
      agent_execution: { status: status, **additional_data }
    })
  end

  def complete_agent_execution(result)
    backend_api_patch("/api/v1/internal/ai/executions/#{@agent_execution['id']}", {
      agent_execution: {
        status: 'completed',
        output_data: result[:output_data],
        cost_usd: result[:cost],
        duration_ms: result[:duration_ms],
        tokens_used: result[:tokens_used],
        completed_at: Time.current.iso8601
      }
    })

    emit_telemetry("agent_execution_completed", outcome: "success", data: {
      duration_ms: result[:duration_ms], cost: result[:cost]
    })
    trigger_trust_evaluation(result)
  end

  def check_budget_gate
    agent_id = @agent_execution.dig('ai_agent', 'id')
    return nil unless agent_id

    response = backend_api_get("/api/v1/ai/autonomy/budgets/alerts")
    return nil unless response['success']

    alerts = response['data'] || []
    agent_alert = alerts.find { |a| a['agent_id'] == agent_id && a['level'] == 'exhausted' }

    if agent_alert
      { allowed: false, remaining_cents: agent_alert['remaining_cents'] || 0 }
    else
      { allowed: true }
    end
  rescue StandardError => e
    log_warn("Budget gate check failed, allowing execution", error: e.message)
    nil
  end

  def fail_agent_execution(error_message)
    backend_api_patch("/api/v1/internal/ai/executions/#{@agent_execution['id']}", {
      agent_execution: {
        status: 'failed',
        error_message: error_message,
        completed_at: Time.current.iso8601
      }
    })
    emit_telemetry("agent_execution_failed", outcome: "failure", data: { error: error_message })
  end

  def trigger_trust_evaluation(result)
    agent_id = @agent_execution.dig('ai_agent', 'id')
    return unless agent_id

    backend_api_post("/api/v1/ai/autonomy/trust_scores/#{agent_id}/evaluate_from_execution", {
      execution_id: @agent_execution['id'],
      success: result[:success],
      duration_ms: result[:duration_ms],
      cost: result[:cost],
      tokens_used: result[:tokens_used]
    })
  rescue StandardError => e
    log_warn("Trust evaluation after execution failed (non-fatal)", error: e.message)
  end

  def emit_telemetry(event_type, outcome: nil, data: {})
    agent_id = @agent_execution.dig('ai_agent', 'id')
    return unless agent_id

    backend_api_post("/api/v1/ai/autonomy/telemetry", {
      agent_id: agent_id,
      event_category: "action",
      event_type: event_type,
      outcome: outcome,
      correlation_id: @agent_execution['id'],
      event_data: data.merge(execution_id: @agent_execution['id'])
    })
  rescue StandardError => e
    log_warn("Telemetry emission failed (non-fatal)", error: e.message)
  end
end

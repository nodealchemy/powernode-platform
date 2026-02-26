# frozen_string_literal: true

class AiA2aTaskExecutionJob < BaseJob
  include AiJobsConcern
  include AiLlmProxyConcern
  include AiCostCalculationConcern
  include A2aArtifactExtractionConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  def execute(a2a_task_id)
    log_info("Starting A2A task execution", a2a_task_id: a2a_task_id)

    # Fetch the A2A task from backend
    @task = fetch_a2a_task(a2a_task_id)
    return unless @task

    # Validate task state
    unless can_execute_task?
      log_error("Cannot execute A2A task - invalid state", status: @task['status'])
      return
    end

    begin
      # Start the task
      update_task_status('active', started_at: Time.current.iso8601)

      # Execute the task
      result = execute_a2a_task

      if result[:success]
        complete_task(result)
        log_info("A2A task execution completed successfully",
          a2a_task_id: a2a_task_id,
          duration_ms: result[:duration_ms],
          cost: result[:cost]
        )
      else
        fail_task(result[:error], result[:error_code])
        log_error("A2A task execution failed",
          a2a_task_id: a2a_task_id,
          error: result[:error]
        )
      end

    rescue StandardError => e
      fail_task(e.message, 'EXECUTION_ERROR')
      handle_ai_processing_error(e, { a2a_task_id: a2a_task_id })
    end
  end

  private

  def fetch_a2a_task(task_id)
    response = backend_api_get("/api/v1/ai/a2a/tasks/#{task_id}/details")

    if response['success']
      response['data']['task']
    else
      log_error("Failed to fetch A2A task", task_id: task_id)
      nil
    end
  end

  def can_execute_task?
    return false unless @task

    status = @task['status']
    valid_statuses = %w[pending active]

    unless valid_statuses.include?(status)
      log_warn("A2A task not in executable state",
        status: status,
        valid_statuses: valid_statuses
      )
      return false
    end

    # Validate we have a target agent
    unless @task['to_agent_id'] || @task['to_agent_card_id']
      log_error("A2A task missing target agent")
      return false
    end

    true
  end

  def update_task_status(status, additional_data = {})
    payload = {
      status: status,
      **additional_data
    }

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end

  def execute_a2a_task
    start_time = Time.current

    # Get the target agent
    agent = fetch_target_agent
    return { success: false, error: 'Target agent not found' } unless agent

    # Get provider for the agent
    provider = agent['ai_provider'] || fetch_default_provider
    return { success: false, error: 'No AI provider configured' } unless provider

    # Build execution context with memory injection
    context = build_execution_context(agent)

    # Build prompt from A2A message
    prompt = build_prompt_from_message

    log_info("Executing A2A task",
      agent_name: agent['name'],
      provider_name: provider['name']
    )

    # Call AI provider via LLM proxy
    ai_response = call_ai_provider_for_a2a(provider, nil, prompt, context)

    execution_time = Time.current - start_time
    duration_ms = (execution_time * 1000).to_i

    if ai_response[:success]
      # Store execution in experiential memory
      store_execution_memory(agent, ai_response, true)

      {
        success: true,
        output: {
          'content' => ai_response[:response],
          'model_used' => ai_response[:model],
          'tokens_used' => ai_response.dig(:metadata, :tokens_used) || 0
        },
        artifacts: extract_artifacts(ai_response[:response]),
        duration_ms: duration_ms,
        cost: ai_response[:cost] || 0.0,
        tokens_used: ai_response.dig(:metadata, :tokens_used) || 0
      }
    else
      # Store failure in experiential memory
      store_execution_memory(agent, ai_response, false)

      {
        success: false,
        error: ai_response[:error] || 'Unknown AI provider error',
        error_code: 'AI_PROVIDER_ERROR',
        duration_ms: duration_ms
      }
    end
  end

  def fetch_target_agent
    agent_id = @task['to_agent_id']
    return nil unless agent_id

    response = backend_api_get("/api/v1/ai/agents/#{agent_id}")
    response['success'] ? response['data']['agent'] : nil
  end

  def fetch_default_provider
    response = backend_api_get("/api/v1/ai/providers", { status: 'active', limit: 1 })
    return nil unless response['success']

    response['data']['items']&.first
  end

  def build_execution_context(agent)
    context = []

    # Add system prompt from agent
    system_prompt = agent['system_prompt'] || agent.dig('configuration', 'system_prompt')
    if system_prompt.present?
      context << { role: 'system', content: system_prompt }
    end

    # Add conversation history from task
    history = @task['history'] || []
    history.each do |msg|
      context << {
        role: msg['role'] || 'user',
        content: extract_text_from_parts(msg['parts'])
      }
    end

    # Inject memory context
    memory_context = fetch_memory_context(agent)
    if memory_context.present?
      context.unshift({
        role: 'system',
        content: "RELEVANT CONTEXT:\n#{memory_context}"
      })
    end

    context
  end

  def fetch_memory_context(agent)
    response = backend_api_post("/api/v1/ai/agents/#{agent['id']}/memory/inject", {
      task_id: @task['task_id'],
      token_budget: 2000
    })

    return nil unless response['success']

    response['data']['context']
  rescue StandardError => e
    log_warn("Failed to fetch memory context: #{e.message}")
    nil
  end

  def build_prompt_from_message
    message = @task['message'] || {}
    parts = message['parts'] || []

    input = @task['input'] || {}

    text_parts = parts.select { |p| p['type'] == 'text' }.map { |p| p['text'] }
    text_parts << input['text'] if input['text'].present? && text_parts.empty?

    text_parts.join("\n\n")
  end

  def extract_text_from_parts(parts)
    return '' unless parts.is_a?(Array)

    parts.select { |p| p['type'] == 'text' }
         .map { |p| p['text'] }
         .join("\n")
  end

  def call_ai_provider_for_a2a(provider, _credentials, prompt, context)
    agent_id = @task['to_agent_id']

    messages = context.map { |c| { role: c['role'] || c[:role], content: c['content'] || c[:content] } }
    messages << { role: "user", content: prompt }

    result = llm_proxy.execute_tool_loop(
      agent_id: agent_id,
      messages: messages
    )

    content = result['content'] || result[:content]
    usage = result['usage'] || result[:usage] || {}
    tokens = usage['total_tokens'] || usage[:total_tokens] || 0

    {
      success: true,
      response: content,
      model: result['model'] || result[:model],
      cost: result['cost'] || result[:cost] || 0.0,
      metadata: { tokens_used: tokens }
    }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def store_execution_memory(agent, response, success)
    backend_api_post("/api/v1/ai/agents/#{agent['id']}/memory", {
      memory_type: 'experiential',
      content: {
        'task_id' => @task['task_id'],
        'input_summary' => @task.dig('input', 'text')&.truncate(200),
        'output_summary' => response[:response]&.truncate(200),
        'success' => success,
        'error' => response[:error]
      },
      outcome_success: success,
      importance: success ? 0.5 : 0.7,
      tags: ['a2a_task', success ? 'success' : 'failure']
    })
  rescue StandardError => e
    log_warn("Failed to store execution memory: #{e.message}")
  end

  def complete_task(result)
    payload = {
      status: 'completed',
      output: result[:output],
      artifacts: result[:artifacts],
      completed_at: Time.current.iso8601,
      duration_ms: result[:duration_ms],
      cost: result[:cost],
      tokens_used: result[:tokens_used]
    }

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end

  def fail_task(error_message, error_code = nil)
    payload = {
      status: 'failed',
      error_message: error_message,
      error_code: error_code || 'EXECUTION_ERROR',
      completed_at: Time.current.iso8601
    }

    backend_api_patch("/api/v1/ai/a2a/tasks/#{@task['task_id']}", payload)
  end
end

# frozen_string_literal: true

class AiA2aTaskExecutionJob < BaseJob
  include AiJobsConcern

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

    # Call AI provider
    ai_response = call_ai_provider_for_a2a(provider, credentials, prompt, context)

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

    # Also include simplified input
    input = @task['input'] || {}

    # Combine all text parts
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

  def call_ai_provider_for_a2a(provider, credentials, prompt, context)
    provider_type = provider['provider_type']&.downcase || 'custom'

    case provider_type
    when 'openai'
      call_openai_provider(credentials, prompt, context)
    when 'anthropic'
      call_anthropic_provider(credentials, prompt, context)
    when 'ollama', 'custom'
      if ollama_compatible_provider?(provider, credentials)
        call_ollama_provider(credentials, prompt, context)
      else
        call_generic_provider(provider, credentials, prompt, context)
      end
    else
      call_generic_provider(provider, credentials, prompt, context)
    end
  end

  def extract_artifacts(response)
    artifacts = []

    # Extract code blocks as artifacts
    response.to_s.scan(/```(\w+)?\n(.*?)```/m) do |lang, code|
      artifacts << {
        'id' => SecureRandom.uuid,
        'name' => "code_#{artifacts.size + 1}.#{lang || 'txt'}",
        'mime_type' => mime_type_for_language(lang),
        'parts' => [{ 'type' => 'text', 'text' => code }]
      }
    end

    # Extract JSON blocks as data artifacts
    response.to_s.scan(/```json\n(.*?)```/m) do |json|
      parsed_data = begin
        JSON.parse(json[0])
      rescue JSON::ParserError
        json[0]
      end
      artifacts << {
        'id' => SecureRandom.uuid,
        'name' => "data_#{artifacts.size + 1}.json",
        'mime_type' => 'application/json',
        'parts' => [{ 'type' => 'data', 'data' => parsed_data }]
      }
    end

    artifacts
  end

  def mime_type_for_language(lang)
    case lang&.downcase
    when 'python', 'py' then 'text/x-python'
    when 'javascript', 'js' then 'text/javascript'
    when 'typescript', 'ts' then 'text/typescript'
    when 'ruby', 'rb' then 'text/x-ruby'
    when 'json' then 'application/json'
    when 'yaml', 'yml' then 'text/yaml'
    when 'html' then 'text/html'
    when 'css' then 'text/css'
    when 'sql' then 'text/x-sql'
    when 'bash', 'sh' then 'text/x-shellscript'
    else 'text/plain'
    end
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

  # Reuse AI provider methods from AiAgentExecutionJob
  # These methods are included via AiJobsConcern or can be extracted to a shared module

  def call_openai_provider(credentials, prompt, context)
    start_time = Time.current

    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'gpt-3.5-turbo'

    return { success: false, error: 'OpenAI API key not configured' } unless api_key

    messages = context + [{ role: 'user', content: prompt }]

    begin
      response = make_http_request(
        'https://api.openai.com/v1/chat/completions',
        method: :post,
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: model,
          messages: messages,
          max_tokens: 2000
        }.to_json,
        timeout: 90
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        {
          success: true,
          response: data.dig('choices', 0, 'message', 'content') || 'No response generated',
          model: model,
          metadata: {
            tokens_used: data.dig('usage', 'total_tokens') || 0,
            response_time_ms: response_time
          },
          cost: (data.dig('usage', 'total_tokens').to_i / 1000.0) * 0.002
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: "OpenAI API error: #{error_data.dig('error', 'message') || response.body}" }
      end
    rescue StandardError => e
      { success: false, error: "OpenAI connection failed: #{e.message}" }
    end
  end

  def call_anthropic_provider(credentials, prompt, context)
    start_time = Time.current

    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'claude-3-sonnet-20240229'

    return { success: false, error: 'Anthropic API key not configured' } unless api_key

    system_message = context.find { |m| m[:role] == 'system' }&.dig(:content) || "You are a helpful AI assistant."
    user_messages = context.reject { |m| m[:role] == 'system' } + [{ role: 'user', content: prompt }]

    begin
      response = make_http_request(
        'https://api.anthropic.com/v1/messages',
        method: :post,
        headers: {
          'x-api-key' => api_key,
          'Content-Type' => 'application/json',
          'anthropic-version' => '2023-06-01'
        },
        body: {
          model: model,
          max_tokens: 2000,
          system: system_message,
          messages: user_messages
        }.to_json,
        timeout: 90
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        {
          success: true,
          response: data.dig('content', 0, 'text') || 'No response generated',
          model: model,
          metadata: {
            tokens_used: (data.dig('usage', 'output_tokens') || 0) + (data.dig('usage', 'input_tokens') || 0),
            response_time_ms: response_time
          },
          cost: (data.dig('usage', 'input_tokens').to_i / 1000.0) * 0.003 + (data.dig('usage', 'output_tokens').to_i / 1000.0) * 0.015
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: "Anthropic API error: #{error_data.dig('error', 'message') || response.body}" }
      end
    rescue StandardError => e
      { success: false, error: "Anthropic connection failed: #{e.message}" }
    end
  end

  def call_ollama_provider(credentials, prompt, context)
    start_time = Time.current

    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    base_url = decrypted_creds['base_url'] || 'http://localhost:11434'
    model = decrypted_creds['model'] || 'llama2'

    messages = context.dup
    messages << { role: 'user', content: prompt }

    begin
      response = make_http_request(
        "#{base_url}/api/chat",
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: {
          model: model,
          messages: messages,
          stream: false
        }.to_json,
        timeout: 300
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i == 200
        data = JSON.parse(response.body)
        content = data.dig('message', 'content')

        if content && !content.empty?
          {
            success: true,
            response: content,
            model: model,
            metadata: {
              tokens_used: data.dig('eval_count') || 0,
              response_time_ms: response_time
            },
            cost: 0.0
          }
        else
          { success: false, error: 'Empty response from Ollama' }
        end
      else
        { success: false, error: "Ollama API error: #{response.code} - #{response.body}" }
      end
    rescue StandardError => e
      { success: false, error: "Ollama connection failed: #{e.message}" }
    end
  end

  def call_generic_provider(provider, credentials, prompt, context)
    # Fallback to OpenAI-compatible format
    call_openai_provider(credentials, prompt, context)
  end

  def ollama_compatible_provider?(provider, credentials)
    provider_name = provider['name']&.downcase || ''
    provider_name.include?('ollama')
  end
end

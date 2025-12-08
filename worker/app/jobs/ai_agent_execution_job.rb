# frozen_string_literal: true

class AiAgentExecutionJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_agents', retry: 3

  def execute(agent_execution_id)
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
            combined_response = current_response # Keep building response
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

  def build_multi_turn_prompt(agent, input_data, conversation_history, turn_number)
    if turn_number == 1
      # First turn - use original prompt
      return build_agent_prompt(agent, input_data)
    end

    # Subsequent turns - include conversation context
    base_prompt = agent['prompt_template'] || agent['system_prompt'] || ''

    # Replace variables in base prompt
    rendered_prompt = base_prompt.dup
    input_data.each do |key, value|
      rendered_prompt.gsub!("{{#{key}}}", value.to_s)
      rendered_prompt.gsub!("{#{key}}", value.to_s)
    end

    # Add conversation history
    rendered_prompt += "\n\n--- CONVERSATION HISTORY ---\n"
    conversation_history.each do |turn|
      rendered_prompt += "\nTurn #{turn[:turn]}:\n"
      rendered_prompt += "Response: #{turn[:response]}\n"
    end

    # Add follow-up instruction
    rendered_prompt += "\n--- FOLLOW-UP REQUEST ---\n"
    rendered_prompt += generate_follow_up_instruction(conversation_history.last[:response], agent)

    rendered_prompt
  end

  def analyze_response_for_follow_up(response, agent)
    # Configuration for what constitutes incomplete responses
    follow_up_config = agent.dig('configuration', 'multi_turn', 'follow_up_triggers') || {}

    # Default triggers for incomplete responses
    default_triggers = {
      'min_length' => 50,
      'question_patterns' => ['?', 'clarify', 'more details', 'specify', 'which', 'what kind'],
      'incomplete_patterns' => ['...', 'etc.', 'and more', 'among others', 'for example'],
      'insufficient_patterns' => ['brief', 'summary', 'overview', 'in general']
    }

    triggers = default_triggers.merge(follow_up_config)

    # Check response length
    if response.length < triggers['min_length']
      return {
        needs_follow_up: true,
        reason: 'Response too short - requesting more detailed information'
      }
    end

    # Check for question patterns (AI asking for clarification)
    triggers['question_patterns'].each do |pattern|
      if response.downcase.include?(pattern.downcase)
        return {
          needs_follow_up: true,
          reason: "AI requested clarification or asked a question - pattern: #{pattern}"
        }
      end
    end

    # Check for incomplete patterns
    triggers['incomplete_patterns'].each do |pattern|
      if response.downcase.include?(pattern.downcase)
        return {
          needs_follow_up: true,
          reason: "Response appears incomplete - pattern: #{pattern}"
        }
      end
    end

    # Check for insufficient detail patterns
    triggers['insufficient_patterns'].each do |pattern|
      if response.downcase.include?(pattern.downcase)
        return {
          needs_follow_up: true,
          reason: "Response lacks sufficient detail - pattern: #{pattern}"
        }
      end
    end

    # Response appears satisfactory
    { needs_follow_up: false, reason: 'Response appears complete and satisfactory' }
  end

  def generate_follow_up_instruction(previous_response, agent)
    # Analyze what kind of follow-up is needed
    if previous_response.include?('?')
      return "The previous response asked questions. Please provide more specific details and examples to fully address the original request without asking additional questions."
    elsif previous_response.length < 100
      return "The previous response was quite brief. Please provide a more comprehensive and detailed response that fully addresses all aspects of the original request."
    elsif previous_response.downcase.include?('clarify') || previous_response.downcase.include?('specify')
      return "The previous response requested clarification. Please provide the most comprehensive response possible based on the original request, including specific examples and detailed explanations."
    else
      return "Please expand on the previous response with more specific details, examples, and comprehensive coverage of the topic."
    end
  end

  def build_agent_prompt(agent, input_data)
    # PRIORITY 1: Use pre-processed prompt from workflow node executor
    if input_data['prompt'].present?
      log_info("Using pre-processed prompt from node executor",
        prompt_preview: input_data['prompt'][0..200]
      )
      return input_data['prompt']
    end

    # PRIORITY 2: Build prompt from agent configuration (fallback)
    log_info("No pre-processed prompt found, building from agent configuration")

    agent_config = agent['configuration'] || {}
    base_prompt = agent['prompt_template'] ||
                  agent['system_prompt'] ||
                  agent_config['prompt_template'] ||
                  agent_config['system_prompt'] ||
                  ''

    if base_prompt.present?
      log_info("Building prompt with base_prompt", base_prompt_preview: base_prompt[0..100])
    end
    log_info("Available input data keys", input_keys: input_data.keys.inspect)

    # If no base prompt found, create a basic prompt from input data
    if base_prompt.blank?
      log_warn("No prompt template found in agent configuration")

      # Create a basic prompt from the available input data
      if input_data['topic'].present?
        base_prompt = "Please provide comprehensive information about: {{topic}}"
      elsif input_data['input'].present?
        base_prompt = "Please respond to: {{input}}"
      else
        base_prompt = "Please provide a helpful response based on the input provided."
      end
    end

    # Replace variables in prompt with input data
    rendered_prompt = base_prompt.dup
    input_data.each do |key, value|
      rendered_prompt.gsub!("{{#{key}}}", value.to_s)
      rendered_prompt.gsub!("{#{key}}", value.to_s)
    end

    # Add context if available
    if input_data['context']
      rendered_prompt += "\n\nContext: #{input_data['context']}"
    end

    # Add user input if available
    if input_data['user_input'] && !input_data['prompt']
      rendered_prompt += "\n\nUser Input: #{input_data['user_input']}"
    end

    if rendered_prompt.present?
      log_info("Final rendered prompt", prompt_preview: rendered_prompt[0..200])
    end
    rendered_prompt
  end

  def build_agent_context(input_data)
    # Build comprehensive conversation context with standardized communication protocols
    context = []

    # 1. Add system message with agent's specific prompt
    agent = @agent_execution['ai_agent']
    agent_config = agent['configuration'] || {}
    system_prompt = agent['system_prompt'] || agent_config['system_prompt']

    if system_prompt.present?
      log_info("Adding agent system prompt to context",
        system_prompt_preview: system_prompt[0..100]
      )
      context << {
        role: 'system',
        content: system_prompt
      }
    end

    # 2. Add standardized interaction handling instructions
    standardized_instructions = build_standardized_instructions(agent, input_data)
    if standardized_instructions.present?
      log_info("Adding standardized instructions to context")
      context << {
        role: 'system',
        content: standardized_instructions
      }
    end

    # 3. Add conversation history if available
    if input_data['conversation_history']
      input_data['conversation_history'].each do |msg|
        context << {
          role: msg['role'] || 'user',
          content: msg['content']
        }
      end
    end

    # 4. Add workflow context if this is part of a workflow
    if input_data['_workflow_context']
      workflow_context = build_workflow_context_instructions(input_data['_workflow_context'])
      if workflow_context.present?
        log_info("Adding workflow context instructions")
        context << {
          role: 'system',
          content: workflow_context
        }
      end
    end

    log_info("Built comprehensive context", context_messages: context.length)
    context
  end

  # Build standardized interaction handling instructions
  def build_standardized_instructions(agent, input_data)
    agent_type = agent['agent_type'] || 'assistant'

    base_instructions = [
      "IMPORTANT COMMUNICATION STANDARDS:",
      "- Provide direct, specific responses based on the exact input provided",
      "- Do not ask clarifying questions unless absolutely necessary",
      "- Focus on delivering the requested content or analysis",
      "- Use clear, structured formatting when appropriate",
      "- Ensure your response directly addresses the user's request"
    ]

    # Add agent-type specific instructions
    type_specific = case agent_type
    when 'content_generator'
      [
        "- Generate actual content, not instructions about content",
        "- Create complete, ready-to-use material",
        "- Follow any specified tone, style, or format requirements"
      ]
    when 'data_analyst', 'code_assistant'
      [
        "- Provide specific analysis with concrete findings",
        "- Include relevant data points and insights",
        "- Present results in a clear, actionable format"
      ]
    when 'workflow_optimizer'
      [
        "- Focus on practical optimization recommendations",
        "- Provide specific steps and improvements",
        "- Consider both efficiency and effectiveness"
      ]
    else
      [
        "- Provide helpful, accurate, and complete responses",
        "- Adapt your communication style to the request type"
      ]
    end

    # Add workflow-specific instructions if in workflow context
    if input_data['_workflow_context']
      workflow_instructions = [
        "",
        "WORKFLOW EXECUTION CONTEXT:",
        "- This is part of an automated workflow execution",
        "- Your response will be processed by subsequent workflow nodes",
        "- Ensure your output is well-structured and contains the requested information",
        "- Avoid meta-commentary about the workflow itself"
      ]
      base_instructions.concat(workflow_instructions)
    end

    (base_instructions + type_specific).join("\n")
  end

  # Build workflow context instructions
  def build_workflow_context_instructions(workflow_context)
    return nil unless workflow_context.is_a?(Hash)

    workflow_name = workflow_context['workflow_name']
    node_id = workflow_context['node_id']

    instructions = []
    instructions << "WORKFLOW CONTEXT:"
    instructions << "- Workflow: #{workflow_name}" if workflow_name
    instructions << "- Current node: #{node_id}" if node_id
    instructions << "- Execute your specific role in this workflow step"
    instructions << "- Provide complete output that subsequent nodes can process"

    instructions.join("\n")
  end

  # Build AI service configuration for multi-turn execution
  def build_ai_service_config(agent, provider, credentials)
    context = build_agent_context({})

    {
      provider: provider,
      credentials: credentials,
      context: context,
      provider_type: provider['provider_type']&.downcase || 'custom',
      agent: agent
    }
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

  # Add provider-specific standardization instructions
  def add_provider_standardization_context(context, provider_type)
    enhanced_context = context.dup

    provider_instructions = case provider_type
    when 'ollama', 'custom'
      build_ollama_standardization_prompt
    when 'openai'
      build_openai_standardization_prompt
    when 'anthropic'
      build_anthropic_standardization_prompt
    else
      build_generic_standardization_prompt
    end

    if provider_instructions.present?
      log_info("Adding standardization instructions", provider_type: provider_type)
      enhanced_context << {
        role: 'system',
        content: provider_instructions
      }
    end

    enhanced_context
  end

  def build_ollama_standardization_prompt
    <<~PROMPT
      OLLAMA PROVIDER STANDARDIZATION:
      - Provide direct, factual responses without unnecessary preambles
      - Do not include phrases like "I'm ready to help" or "I can assist you"
      - Focus on delivering the specific content or analysis requested
      - Use clear, structured formatting when presenting information
      - Avoid meta-commentary about your capabilities or limitations
      - If the request is for research, provide actual research findings
      - If the request is for content creation, provide the actual content
      - Be concise but comprehensive in your responses
      - Use bullet points or numbered lists for multiple items when appropriate
    PROMPT
  end

  def build_openai_standardization_prompt
    <<~PROMPT
      OPENAI PROVIDER STANDARDIZATION:
      - Provide direct, actionable responses to the specific request
      - Focus on delivering concrete results rather than explanations of what you could do
      - Use structured formatting to organize complex information
      - Be thorough but avoid unnecessary verbosity
      - When asked for research, provide specific facts and data points
      - When asked for content, deliver complete, ready-to-use material
    PROMPT
  end

  def build_anthropic_standardization_prompt
    <<~PROMPT
      ANTHROPIC PROVIDER STANDARDIZATION:
      - Deliver comprehensive, well-structured responses
      - Provide specific, actionable information based on the request
      - Use clear organization and formatting for complex topics
      - Focus on practical, useful output rather than theoretical possibilities
      - When generating content, ensure it's complete and immediately usable
    PROMPT
  end

  def build_generic_standardization_prompt
    <<~PROMPT
      PROVIDER STANDARDIZATION:
      - Respond directly to the specific request without unnecessary introductions
      - Provide concrete, actionable information
      - Use clear formatting and structure
      - Focus on delivering the requested content or analysis
      - Be comprehensive but concise
    PROMPT
  end

  def call_ollama_provider(credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    # Use provider's api_endpoint if available, otherwise use base_url from credentials
    provider = @agent_execution['ai_provider']
    base_url = if provider && provider['api_endpoint'].present?
                 # Extract base URL from provider endpoint (remove path)
                 uri = URI.parse(provider['api_endpoint'])
                 "#{uri.scheme}://#{uri.host}:#{uri.port}"
               else
                 decrypted_creds['base_url'] || 'http://localhost:11434'
               end

    # Use agent-specific model configuration, fall back to credentials, then default
    agent = @agent_execution['ai_agent']
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] ||
            'deepseek-r1:1.5b' # Updated default to match agent configs

    # Build messages array
    messages = context.dup
    messages << { role: 'user', content: prompt }

    # Implement adaptive retry for Ollama timeout issues
    max_retries = 2
    retry_count = 0

    begin
      request_url = "#{base_url}/api/chat"
      request_body = {
        model: model,
        messages: messages,
        stream: false
      }

      # Adaptive timeout: increase timeout on retries
      timeout = 300 + (retry_count * 120) # Start at 5min, add 2min per retry

      log_info("Calling Ollama API",
        url: request_url,
        model: model,
        attempt: retry_count + 1,
        timeout: timeout
      )

      response = make_http_request(
        request_url,
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: request_body.to_json,
        timeout: timeout
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
              prompt_tokens: data.dig('prompt_eval_count') || 0,
              response_time_ms: response_time
            },
            cost: calculate_ollama_cost(data)
          }
        else
          { success: false, error: 'Empty response from Ollama' }
        end
      else
        { success: false, error: "Ollama API error: #{response.code} - #{response.body}" }
      end

    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
      if retry_count < max_retries
        retry_count += 1
        wait_time = retry_count * 10 # Wait 10s, 20s between retries
        log_info("Ollama timeout, retrying",
          attempt: retry_count,
          wait_time: wait_time,
          error: e.message
        )
        sleep(wait_time)
        retry
      else
        log_error("Ollama timeout after #{max_retries} retries", e)
        { success: false, error: "Ollama connection timeout after #{max_retries} retries: #{e.message}" }
      end
    rescue StandardError => e
      { success: false, error: "Ollama connection failed: #{e.message}" }
    end
  end

  def call_openai_provider(credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'gpt-3.5-turbo'

    return { success: false, error: 'OpenAI API key not configured' } unless api_key

    # Build messages array
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
            prompt_tokens: data.dig('usage', 'prompt_tokens') || 0,
            response_time_ms: response_time
          },
          cost: calculate_openai_cost(data, model)
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

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    api_key = decrypted_creds['api_key']
    model = decrypted_creds['model'] || 'claude-3-sonnet-20240229'

    return { success: false, error: 'Anthropic API key not configured' } unless api_key

    # Format for Anthropic API
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
        content = data.dig('content', 0, 'text') || 'No response generated'

        {
          success: true,
          response: content,
          model: model,
          metadata: {
            tokens_used: data.dig('usage', 'output_tokens') || 0,
            prompt_tokens: data.dig('usage', 'input_tokens') || 0,
            response_time_ms: response_time
          },
          cost: calculate_anthropic_cost(data, model)
        }
      else
        error_data = JSON.parse(response.body) rescue {}
        { success: false, error: "Anthropic API error: #{error_data.dig('error', 'message') || response.body}" }
      end

    rescue StandardError => e
      { success: false, error: "Anthropic connection failed: #{e.message}" }
    end
  end

  def call_generic_provider(provider, credentials, prompt, context)
    start_time = Time.current

    # Decrypt credentials
    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return { success: false, error: 'Failed to decrypt credentials' } unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']

    # Extract provider configuration
    api_endpoint = provider['api_endpoint'] || decrypted_creds['api_endpoint'] || decrypted_creds['base_url']
    return { success: false, error: "No API endpoint configured for provider #{provider['name']}" } unless api_endpoint.present?

    # Determine auth method and headers
    headers = build_generic_auth_headers(provider, decrypted_creds)
    headers['Content-Type'] = 'application/json'
    headers['Accept'] = 'application/json'

    # Build request body based on provider configuration
    request_body = build_generic_request_body(provider, decrypted_creds, prompt, context)

    # Determine model
    agent = @agent_execution['ai_agent']
    model = agent&.dig('configuration', 'model') ||
            decrypted_creds['model'] ||
            provider.dig('configuration', 'default_model') ||
            'default'

    log_info("Calling generic AI provider",
      provider_name: provider['name'],
      api_endpoint: api_endpoint,
      model: model
    )

    begin
      # Make the API request
      timeout = provider.dig('configuration', 'timeout') || 120
      response = make_http_request(
        api_endpoint,
        method: :post,
        headers: headers,
        body: request_body.to_json,
        timeout: timeout
      )

      response_time = ((Time.current - start_time) * 1000).to_i

      if response.code.to_i >= 200 && response.code.to_i < 300
        data = JSON.parse(response.body)

        # Extract response based on provider's response mapping
        extracted_response = extract_generic_response(provider, data)

        if extracted_response[:content].present?
          {
            success: true,
            response: extracted_response[:content],
            model: model,
            metadata: {
              tokens_used: extracted_response[:tokens_used] || 0,
              prompt_tokens: extracted_response[:prompt_tokens] || 0,
              response_time_ms: response_time,
              provider_response: data
            },
            cost: calculate_generic_cost(provider, decrypted_creds, extracted_response)
          }
        else
          { success: false, error: "Empty response from provider #{provider['name']}" }
        end
      else
        error_data = JSON.parse(response.body) rescue { 'message' => response.body }
        error_message = extract_generic_error(provider, error_data) || "API error: #{response.code}"
        { success: false, error: "#{provider['name']} API error: #{error_message}" }
      end

    rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
      log_error("Generic provider timeout", e)
      { success: false, error: "#{provider['name']} connection timeout: #{e.message}" }
    rescue JSON::ParserError => e
      log_error("Failed to parse provider response", e)
      { success: false, error: "Invalid JSON response from #{provider['name']}" }
    rescue StandardError => e
      log_error("Generic provider error", e)
      { success: false, error: "#{provider['name']} connection failed: #{e.message}" }
    end
  end

  def build_generic_auth_headers(provider, credentials)
    headers = {}
    auth_type = provider.dig('configuration', 'auth_type') || credentials['auth_type'] || 'api_key'

    case auth_type.to_s.downcase
    when 'api_key', 'apikey'
      api_key = credentials['api_key']
      header_name = provider.dig('configuration', 'api_key_header') || 'Authorization'
      header_prefix = provider.dig('configuration', 'api_key_prefix') || 'Bearer'

      if api_key.present?
        if header_prefix.present?
          headers[header_name] = "#{header_prefix} #{api_key}"
        else
          headers[header_name] = api_key
        end
      end

    when 'bearer', 'bearer_token'
      token = credentials['api_key'] || credentials['access_token'] || credentials['bearer_token']
      headers['Authorization'] = "Bearer #{token}" if token.present?

    when 'basic', 'basic_auth'
      username = credentials['username'] || credentials['api_key']
      password = credentials['password'] || credentials['api_secret']
      if username.present?
        encoded = Base64.strict_encode64("#{username}:#{password}")
        headers['Authorization'] = "Basic #{encoded}"
      end

    when 'custom_header'
      custom_header_name = provider.dig('configuration', 'custom_header_name')
      custom_header_value = credentials['api_key'] || credentials['custom_header_value']
      if custom_header_name.present? && custom_header_value.present?
        headers[custom_header_name] = custom_header_value
      end

    when 'oauth', 'oauth2'
      # OAuth would typically require a token refresh flow
      access_token = credentials['access_token']
      headers['Authorization'] = "Bearer #{access_token}" if access_token.present?
    end

    # Add any custom headers from provider configuration
    custom_headers = provider.dig('configuration', 'custom_headers') || {}
    headers.merge!(custom_headers)

    headers
  end

  def build_generic_request_body(provider, credentials, prompt, context)
    # Get the request format from provider configuration
    request_format = provider.dig('configuration', 'request_format') || 'openai'
    model = @agent_execution.dig('ai_agent', 'configuration', 'model') ||
            credentials['model'] ||
            provider.dig('configuration', 'default_model')

    case request_format.to_s.downcase
    when 'openai', 'openai_compatible'
      # OpenAI-compatible format (most common)
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000,
        temperature: provider.dig('configuration', 'temperature') || 0.7
      }

    when 'anthropic', 'claude'
      # Anthropic Claude format
      system_message = context.find { |m| m[:role] == 'system' }&.dig(:content)
      user_messages = context.reject { |m| m[:role] == 'system' } + [{ role: 'user', content: prompt }]
      {
        model: model,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000,
        system: system_message,
        messages: user_messages
      }

    when 'ollama'
      # Ollama format
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        stream: false
      }

    when 'simple', 'text'
      # Simple text completion format
      {
        prompt: prompt,
        model: model,
        max_tokens: provider.dig('configuration', 'max_tokens') || 2000
      }

    when 'custom'
      # Custom format - use template from provider configuration
      template = provider.dig('configuration', 'request_template') || {}
      rendered = deep_render_template(template, {
        'prompt' => prompt,
        'model' => model,
        'messages' => context + [{ role: 'user', content: prompt }],
        'system' => context.find { |m| m[:role] == 'system' }&.dig(:content) || ''
      })
      rendered

    else
      # Default to OpenAI format
      messages = context.dup
      messages << { role: 'user', content: prompt }
      {
        model: model,
        messages: messages,
        max_tokens: 2000
      }
    end
  end

  def deep_render_template(template, variables)
    case template
    when Hash
      template.transform_values { |v| deep_render_template(v, variables) }
    when Array
      template.map { |v| deep_render_template(v, variables) }
    when String
      rendered = template.dup
      variables.each do |key, value|
        rendered.gsub!("{{#{key}}}", value.to_s)
        rendered.gsub!("{#{key}}", value.to_s)
      end
      rendered
    else
      template
    end
  end

  def extract_generic_response(provider, response_data)
    response_format = provider.dig('configuration', 'response_format') || 'openai'

    case response_format.to_s.downcase
    when 'openai', 'openai_compatible'
      {
        content: response_data.dig('choices', 0, 'message', 'content'),
        tokens_used: response_data.dig('usage', 'total_tokens'),
        prompt_tokens: response_data.dig('usage', 'prompt_tokens')
      }

    when 'anthropic', 'claude'
      {
        content: response_data.dig('content', 0, 'text'),
        tokens_used: response_data.dig('usage', 'output_tokens'),
        prompt_tokens: response_data.dig('usage', 'input_tokens')
      }

    when 'ollama'
      {
        content: response_data.dig('message', 'content'),
        tokens_used: response_data['eval_count'],
        prompt_tokens: response_data['prompt_eval_count']
      }

    when 'simple', 'text'
      {
        content: response_data['text'] || response_data['completion'] || response_data['response'] || response_data['output'],
        tokens_used: response_data['tokens_used'] || response_data['total_tokens'],
        prompt_tokens: response_data['prompt_tokens']
      }

    when 'custom'
      # Use custom response path from configuration
      content_path = provider.dig('configuration', 'response_content_path') || 'choices.0.message.content'
      tokens_path = provider.dig('configuration', 'response_tokens_path') || 'usage.total_tokens'

      {
        content: dig_path(response_data, content_path),
        tokens_used: dig_path(response_data, tokens_path),
        prompt_tokens: dig_path(response_data, provider.dig('configuration', 'response_prompt_tokens_path'))
      }

    else
      # Try common response paths
      content = response_data.dig('choices', 0, 'message', 'content') ||
                response_data.dig('message', 'content') ||
                response_data.dig('content', 0, 'text') ||
                response_data['text'] ||
                response_data['response'] ||
                response_data['output']

      {
        content: content,
        tokens_used: response_data.dig('usage', 'total_tokens') || response_data['tokens_used'],
        prompt_tokens: response_data.dig('usage', 'prompt_tokens')
      }
    end
  end

  def dig_path(data, path)
    return nil unless path.present? && data.is_a?(Hash)

    path.to_s.split('.').reduce(data) do |obj, key|
      return nil unless obj

      if key =~ /^\d+$/
        obj.is_a?(Array) ? obj[key.to_i] : nil
      else
        obj.is_a?(Hash) ? obj[key] : nil
      end
    end
  end

  def extract_generic_error(provider, error_data)
    error_path = provider.dig('configuration', 'error_message_path') || 'error.message'

    # Try common error paths
    dig_path(error_data, error_path) ||
      error_data.dig('error', 'message') ||
      error_data.dig('error') ||
      error_data['message'] ||
      error_data['detail']
  end

  def calculate_generic_cost(provider, credentials, response)
    # Check if provider has custom pricing configuration
    pricing = provider.dig('configuration', 'pricing') || credentials['pricing'] || {}

    return 0.0 if pricing.empty?

    tokens_used = response[:tokens_used] || 0
    prompt_tokens = response[:prompt_tokens] || 0
    completion_tokens = tokens_used - prompt_tokens

    # Calculate cost based on pricing configuration
    prompt_cost = (prompt_tokens / 1000.0) * (pricing['prompt_cost_per_1k'] || 0)
    completion_cost = (completion_tokens / 1000.0) * (pricing['completion_cost_per_1k'] || 0)

    prompt_cost + completion_cost
  end

  def clean_ai_response(response)
    return response unless response.is_a?(String)

    # Remove <think>...</think> tags and their content
    cleaned = response.gsub(/<think>.*?<\/think>/m, '')

    # Trim excessive whitespace
    cleaned = cleaned.strip

    # Truncate if still too long (max 10KB for safety)
    max_length = 10_000
    if cleaned.length > max_length
      cleaned = cleaned[0...max_length] + "\n\n[Response truncated due to length]"
    end

    cleaned
  end

  def extract_output_data(ai_response)
    # Extract structured output data from AI response
    # Clean the response by removing thinking tags
    cleaned_response = clean_ai_response(ai_response[:response])

    output = {
      'content' => cleaned_response,    # STANDARDIZED: Use 'content' field for consistency
      'response' => cleaned_response,   # Keep 'response' for backward compatibility during transition
      'model_used' => ai_response[:model],
      'tokens_used' => ai_response.dig(:metadata, :tokens_used) || 0,
      'response_time_ms' => ai_response.dig(:metadata, :response_time_ms) || 0,
      'cost_usd' => ai_response[:cost] || 0.0
    }

    # Try to extract structured data if response contains JSON
    begin
      if ai_response[:response] =~ /```json\s*(\{.*?\})\s*```/m
        json_content = $1
        parsed_json = JSON.parse(json_content)
        output['structured_data'] = parsed_json
      end
    rescue JSON::ParserError
      # Ignore JSON parsing errors
    end

    output
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

  # Helper methods for provider detection (reused from conversation job)
  def ollama_compatible_provider?(provider, credentials)
    provider_name = provider['name']&.downcase || ''
    provider_slug = provider['slug']&.downcase || ''

    # Check if name or slug suggests Ollama
    return true if provider_name.include?('ollama') || provider_slug.include?('ollama')

    # Check credentials for Ollama-specific configuration
    has_ollama_config?(credentials)
  end

  def has_ollama_config?(credentials)
    return false unless credentials

    creds_response = backend_api_post("/api/v1/ai/credentials/#{credentials['id']}/decrypt")
    return false unless creds_response['success']

    decrypted_creds = creds_response['data']['credentials']
    base_url = decrypted_creds['base_url'] || ''

    # Ollama typically uses local URLs with port 11434
    base_url.include?(':11434') || (base_url.include?('localhost') && decrypted_creds['model'])
  rescue StandardError
    false
  end

  # Cost calculation methods
  def calculate_ollama_cost(response_data)
    # Ollama is typically free/local, but we can track token usage
    0.0
  end

  def calculate_openai_cost(response_data, model)
    tokens = response_data.dig('usage', 'total_tokens') || 0

    # Simplified cost calculation (would need actual pricing per model)
    case model
    when /gpt-4/
      (tokens / 1000.0) * 0.03
    when /gpt-3.5/
      (tokens / 1000.0) * 0.002
    else
      (tokens / 1000.0) * 0.002
    end
  end

  def calculate_anthropic_cost(response_data, model)
    input_tokens = response_data.dig('usage', 'input_tokens') || 0
    output_tokens = response_data.dig('usage', 'output_tokens') || 0

    # Simplified cost calculation for Claude
    case model
    when /claude-3-opus/
      (input_tokens / 1000.0) * 0.015 + (output_tokens / 1000.0) * 0.075
    when /claude-3-sonnet/
      (input_tokens / 1000.0) * 0.003 + (output_tokens / 1000.0) * 0.015
    else
      (input_tokens / 1000.0) * 0.003 + (output_tokens / 1000.0) * 0.015
    end
  end
end
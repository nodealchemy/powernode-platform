# frozen_string_literal: true

module AiPromptBuildingConcern
  extend ActiveSupport::Concern

  private

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

  def generate_follow_up_instruction(previous_response, _agent)
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
end

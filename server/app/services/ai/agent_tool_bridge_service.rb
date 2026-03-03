# frozen_string_literal: true

module Ai
  # Bridges PlatformApiToolRegistry definitions ↔ LLM function-calling format
  # and provides the shared agentic tool loop.
  #
  # Outbound: converts platform tool definitions to LLM-compatible tools array
  # Inbound:  dispatches tool calls from LLM responses through McpPlatformToolRegistrar
  # Loop:     iterative tool-calling loop shared by McpAgentExecutor and ConversationResponseJob
  #
  # Default behavior: tools enabled for all agents except mcp_client type.
  # Override via agent's mcp_metadata["tool_access"] JSONB:
  #   { "enabled": false, "allowed_tools": ["search_knowledge"], "max_iterations": 5 }
  #
  class AgentToolBridgeService
    MAX_RESULT_SIZE = 50.kilobytes
    DEFAULT_MAX_ITERATIONS = 10
    HARD_MAX_ITERATIONS = 25

    attr_reader :agent, :account

    def initialize(agent:, account: nil)
      @agent = agent
      @account = account || agent.account
      @tool_access_config = agent.mcp_metadata&.dig("tool_access") || {}
    end

    # Whether this agent should receive tools in LLM calls
    def tools_enabled?
      return false if agent.agent_type == "mcp_client"

      if @tool_access_config.key?("enabled")
        return @tool_access_config["enabled"] == true
      end

      true
    end

    # Maximum agentic loop iterations
    def max_iterations
      configured = @tool_access_config["max_iterations"].to_i
      configured = DEFAULT_MAX_ITERATIONS if configured <= 0
      [configured, HARD_MAX_ITERATIONS].min
    end

    # Convert platform tool definitions to LLM function-calling format
    def tool_definitions_for_llm
      @tool_definitions_for_llm ||= build_tool_definitions
    end

    # Dispatch a tool call from an LLM response through the platform tool registrar.
    # Returns a String (JSON) for appending as a tool result message.
    def dispatch_tool_call(tool_call)
      tool_name = tool_call[:name] || tool_call["name"]
      arguments = tool_call[:arguments] || tool_call["arguments"] || {}
      arguments = JSON.parse(arguments) if arguments.is_a?(String)

      Rails.logger.info "[AgentToolBridge] Dispatching tool: #{tool_name} for agent #{agent.id}"

      result = Ai::Tools::McpPlatformToolRegistrar.execute_tool(
        "platform.#{tool_name}",
        params: arguments.stringify_keys,
        account: account,
        user: agent.creator,
        agent_id: agent.id,
        mcp_agent: agent
      )

      truncate_result(result.to_json)
    rescue ArgumentError => e
      Rails.logger.warn "[AgentToolBridge] Unknown tool: #{tool_name} - #{e.message}"
      { error: "Unknown tool: #{tool_name}", message: e.message }.to_json
    rescue ::Mcp::ProtocolService::PermissionDeniedError => e
      Rails.logger.warn "[AgentToolBridge] Permission denied: #{tool_name} - #{e.message}"
      { error: "Permission denied", tool: tool_name, message: e.message }.to_json
    rescue Ai::Introspection::RateLimiter::RateLimitExceeded => e
      Rails.logger.warn "[AgentToolBridge] Rate limited: #{tool_name} - #{e.message}"
      { error: "Rate limit exceeded", tool: tool_name, message: e.message }.to_json
    rescue StandardError => e
      Rails.logger.error "[AgentToolBridge] Tool error: #{tool_name} - #{e.message}"
      { error: "Tool execution failed", tool: tool_name, message: e.message }.to_json
    end

    # Shared agentic tool loop — call LLM with tools, dispatch calls, repeat.
    #
    # @param llm_client [WorkerLlmClient]
    # @param messages [Array<Hash>] conversation messages (mutated in place)
    # @param model [String] model ID
    # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
    # @return [Hash] { content:, usage:, tool_calls_log:, finish_reason: }
    def execute_tool_loop(llm_client:, messages:, model:, **opts)
      tools = tool_definitions_for_llm
      max_iter = max_iterations
      iteration = 0
      accumulated_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
      tool_calls_log = []

      tool_names = tools.map { |t| t[:name] || t.dig(:function, :name) }.compact
      Rails.logger.info "[AgentToolBridge] Starting loop: model=#{model} tools=#{tool_names.length} (#{tool_names.join(', ')}) messages=#{messages.length} system_prompt_length=#{opts[:system_prompt]&.length}"

      loop do
        iteration += 1
        Rails.logger.info "[AgentToolBridge] Iteration #{iteration}/#{max_iter} for agent #{agent.id}"

        # tool_choice only applies to the first iteration (forced tool call);
        # subsequent iterations use auto so the model can generate a text response
        iter_opts = iteration > 1 ? opts.except(:tool_choice) : opts

        response = llm_client.complete_with_tools(
          messages: messages, tools: tools, model: model, **iter_opts
        )

        Rails.logger.info "[AgentToolBridge] Response: has_tool_calls=#{response.has_tool_calls?} finish_reason=#{response.finish_reason} content_length=#{response.content&.length} usage=#{response.usage}"

        accumulate_usage(accumulated_usage, response.usage)

        # Return if text-only response or iteration cap reached
        unless response.has_tool_calls? && iteration < max_iter
          if response.has_tool_calls?
            Rails.logger.warn "[AgentToolBridge] Max iterations (#{max_iter}) reached with pending tool calls"
          end

          return {
            content: response.content,
            usage: accumulated_usage,
            tool_calls_log: tool_calls_log,
            finish_reason: response.finish_reason
          }
        end

        # Dispatch each tool call and append results to conversation
        response.tool_calls.each do |tool_call|
          tool_name = tool_call[:name] || tool_call["name"]
          tool_call_id = tool_call[:id] || tool_call["id"] || SecureRandom.uuid
          call_start = Time.current

          result_json = dispatch_tool_call(tool_call)
          call_duration_ms = ((Time.current - call_start) * 1000).round

          tool_calls_log << {
            iteration: iteration, tool: tool_name,
            duration_ms: call_duration_ms,
            result_preview: result_json.to_s.truncate(200)
          }

          Rails.logger.info "[AgentToolBridge] Tool #{tool_name} completed in #{call_duration_ms}ms"

          messages << {
            role: "assistant", content: nil,
            tool_calls: [{
              id: tool_call_id,
              name: tool_name,
              arguments: tool_call[:arguments] || tool_call["arguments"] || {}
            }]
          }
          messages << { role: "tool", tool_call_id: tool_call_id, content: result_json }
        end
      end
    end

    # Extended agentic loop with optional reasoning, reflection, and evaluation.
    #
    # @param llm_client [WorkerLlmClient]
    # @param messages [Array<Hash>] conversation messages
    # @param model [String] model ID
    # @param reasoning_mode [Symbol, String, nil] :chain_of_thought, :plan_and_execute, or nil
    # @param reflection_enabled [Boolean] run self-critique after execution
    # @param evaluation_config [Hash, nil] { enabled: true, evaluator_model: "...", max_revisions: 2 }
    # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
    # @return [Hash] { content:, usage:, tool_calls_log:, finish_reason:, reasoning:, reflection:, evaluation: }
    def execute_with_reasoning(llm_client:, messages:, model:, reasoning_mode: nil, reflection_enabled: false, evaluation_config: nil, **opts)
      reasoning_result = nil
      reflection_result = nil
      evaluation_result = nil
      task_text = messages.last&.dig(:content) || messages.last&.dig("content") || ""

      # Phase 1: Pre-execution reasoning
      if reasoning_mode.present?
        reasoning_mode = reasoning_mode.to_sym
        Rails.logger.info "[AgentToolBridge] Reasoning mode: #{reasoning_mode} for agent #{agent.id}"

        case reasoning_mode
        when :chain_of_thought
          cot_service = Ai::Reasoning::ChainOfThoughtService.new(account: account)
          reasoning_result = cot_service.reason(
            task: task_text, llm_client: llm_client, model: model, **opts
          )

          # Inject reasoning into messages
          if reasoning_result[:reasoning_steps].present?
            reasoning_text = cot_service.format_reasoning_for_injection(reasoning_result)
            messages << { role: "assistant", content: reasoning_text }
            messages << { role: "user", content: "Based on this reasoning, please proceed with the task." }
          end

        when :star
          star_service = Ai::Reasoning::StarReasoningService.new(account: account)
          reasoning_result = star_service.reason(
            task: task_text,
            context: extract_context_from_messages(messages),
            llm_client: llm_client, model: model, **opts
          )

          if reasoning_result[:confidence] > 0.0
            reasoning_text = star_service.format_reasoning_for_injection(reasoning_result)
            messages << { role: "assistant", content: reasoning_text }
            messages << { role: "user", content: "Based on this STAR analysis, proceed with the task. Pay special attention to the implicit constraints and success criteria identified in the Task section." }
          end

        when :plan_and_execute
          plan_service = Ai::Planning::TaskDecompositionService.new(account: account)
          plan = plan_service.decompose(
            task: task_text, llm_client: llm_client, model: model, **opts
          )

          if plan[:valid] && plan[:subtasks].present?
            executor = Ai::Planning::PlanExecutorService.new(account: account, user: agent.creator)
            dag_execution = executor.execute_plan(
              plan: plan, agent_id: agent.id, input_context: { task: task_text }
            )
            reasoning_result = { plan: plan, dag_execution_id: dag_execution.id }

            # Use DAG results as context
            if dag_execution.status == "completed"
              outputs = dag_execution.final_outputs || {}
              synthesis = outputs.map { |node_id, r| "#{node_id}: #{r[:output].to_s.truncate(500)}" }.join("\n")
              messages << { role: "assistant", content: "Subtask results:\n#{synthesis}" }
              messages << { role: "user", content: "Please synthesize these results into a final response." }
            end
          end
        end
      end

      # Phase 2: Execute tool loop
      result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)

      # Phase 3: Post-execution reflection
      if reflection_enabled
        Rails.logger.info "[AgentToolBridge] Running reflection for agent #{agent.id}"
        reflection_service = Ai::Reasoning::ReflectionService.new(account: account)
        reflection_result = reflection_service.reflect(
          task: task_text, output: result[:content],
          llm_client: llm_client, model: model, **opts
        )

        # Re-execute if reflection says to retry
        if reflection_result[:should_retry] && result[:content].present?
          Rails.logger.info "[AgentToolBridge] Reflection triggered retry for agent #{agent.id}"
          feedback = "Self-critique feedback:\n- Issues: #{reflection_result[:issues].join(', ')}\n- Improvements: #{reflection_result[:improvements].join(', ')}\nPlease address these issues."
          messages << { role: "assistant", content: result[:content] }
          messages << { role: "user", content: feedback }
          result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)
        end
      end

      # Phase 4: Output evaluation
      eval_config = evaluation_config || agent.mcp_metadata&.dig("evaluation") || {}
      if eval_config["enabled"]
        Rails.logger.info "[AgentToolBridge] Running output evaluation for agent #{agent.id}"
        evaluator = Ai::Reasoning::OutputEvaluatorService.new(account: account)
        max_revisions = eval_config["max_revisions"] || 2
        revision_count = 0

        loop do
          evaluation_result = evaluator.evaluate(
            task: task_text, output: result[:content],
            llm_client: llm_client, model: eval_config["evaluator_model"] || model, **opts
          )

          break if evaluation_result[:verdict] == "pass"
          break if evaluation_result[:verdict] == "reject"
          break if revision_count >= max_revisions

          # Revise
          revision_count += 1
          messages << { role: "assistant", content: result[:content] }
          messages << { role: "user", content: "Evaluator feedback: #{evaluation_result[:feedback]}\nPlease revise your response." }
          result = execute_tool_loop(llm_client: llm_client, messages: messages, model: model, **opts)
        end
      end

      result.merge(
        reasoning: reasoning_result,
        reflection: reflection_result,
        evaluation: evaluation_result
      )
    end

    private

    # Extract any pre-injected context from the message history so STAR
    # can reason about both the task and the surrounding context.
    def extract_context_from_messages(messages)
      context_parts = messages.select { |m| m[:role] == "system" || m["role"] == "system" }
                              .map { |m| m[:content] || m["content"] }
                              .compact

      # Also pull context from assistant messages that look like injected context
      messages.select { |m| (m[:role] || m["role"]) == "assistant" }
              .each do |m|
        content = m[:content] || m["content"]
        context_parts << content if content.present? && content.length > 100
      end

      context_parts.join("\n\n").presence
    end

    def allowed_tool_names
      allowed = @tool_access_config["allowed_tools"]
      return nil if allowed.blank? || allowed == ["*"]

      allowed
    end

    def build_tool_definitions
      definitions = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)

      if (allowed = allowed_tool_names)
        definitions = definitions.select { |d| allowed.include?(d[:name].to_s) }
      end

      definitions.map { |defn| convert_to_llm_tool(defn) }
    end

    def convert_to_llm_tool(definition)
      params = definition[:parameters] || {}
      params = params.except(:action, "action")

      {
        name: definition[:name].to_s,
        description: definition[:description].to_s,
        parameters: convert_to_json_schema(params)
      }
    end

    def convert_to_json_schema(parameters)
      return { type: "object", properties: {}, required: [] } if parameters.blank?

      properties = {}
      required = []

      parameters.each do |param_name, param_def|
        next unless param_def.is_a?(Hash)

        prop = { type: param_def[:type] || "string" }
        prop[:description] = param_def[:description] if param_def[:description].present?
        prop[:enum] = param_def[:enum] if param_def[:enum].present?

        # OpenAI requires `items` on array types and `properties` on object types
        if prop[:type] == "array" && param_def[:items].nil?
          prop[:items] = { type: "string" }
        elsif prop[:type] == "array" && param_def[:items]
          prop[:items] = param_def[:items]
        end

        if prop[:type] == "object" && param_def[:properties].nil?
          prop[:additionalProperties] = true
        elsif prop[:type] == "object" && param_def[:properties]
          prop[:properties] = param_def[:properties]
        end

        properties[param_name.to_s] = prop
        required << param_name.to_s if param_def[:required]
      end

      { type: "object", properties: properties, required: required }
    end

    def accumulate_usage(accumulated, response_usage)
      return unless response_usage

      accumulated[:prompt_tokens] += (response_usage[:prompt_tokens] || 0)
      accumulated[:completion_tokens] += (response_usage[:completion_tokens] || 0)
      accumulated[:total_tokens] += (response_usage[:total_tokens] || 0)
    end

    def truncate_result(json_string)
      return json_string if json_string.bytesize <= MAX_RESULT_SIZE

      truncated = json_string.byteslice(0, MAX_RESULT_SIZE)
      "#{truncated}... [truncated, #{json_string.bytesize} bytes total]"
    end
  end
end

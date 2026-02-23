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
    # @param llm_client [Ai::Llm::Client]
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

      loop do
        iteration += 1
        Rails.logger.info "[AgentToolBridge] Iteration #{iteration}/#{max_iter} for agent #{agent.id}"

        response = llm_client.complete_with_tools(
          messages: messages, tools: tools, model: model, **opts
        )

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

    private

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

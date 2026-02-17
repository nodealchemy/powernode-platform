# frozen_string_literal: true

module Ai
  module TeamExecutionSupport
    module ToolExecution
      extend ActiveSupport::Concern
      include Ai::ToolCallExtraction

      MAX_TOOL_ROUNDS = 10
      MAX_TOOL_CALLS_TOTAL = 30
      TOOL_CALL_TIMEOUT = 30

      private

      def tools_enabled?
        team_config["tools_enabled"] != false
      end

      def provider_type_for(agent)
        agent.provider.provider_type
      end

      # Convert platform tools to OpenAI function-calling format
      def platform_tool_definitions(agent)
        raw_defs = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)
        raw_defs.map do |defn|
          {
            type: "function",
            function: {
              name: defn[:name],
              description: defn[:description],
              parameters: convert_params_to_json_schema(defn[:parameters])
            }
          }
        end
      rescue StandardError => e
        log_execution("[ToolExecution] Failed to build tool definitions: #{e.message}")
        []
      end

      # Convert platform tools to Anthropic tool format
      def anthropic_tool_definitions(agent)
        raw_defs = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)
        raw_defs.map do |defn|
          {
            name: defn[:name],
            description: defn[:description],
            input_schema: convert_params_to_json_schema(defn[:parameters])
          }
        end
      rescue StandardError => e
        log_execution("[ToolExecution] Failed to build Anthropic tool definitions: #{e.message}")
        []
      end

      # Convert internal parameter definitions to JSON Schema format
      def convert_params_to_json_schema(params)
        return { type: "object", properties: {}, required: [] } unless params.is_a?(Hash)

        properties = {}
        required = []

        params.each do |key, spec|
          next if key.to_s == "action" # action is derived from tool name

          prop = { type: spec[:type] || "string" }
          prop[:description] = spec[:description] if spec[:description]
          prop[:items] = spec[:items] || { type: "string" } if prop[:type] == "array"
          properties[key.to_s] = prop
          required << key.to_s if spec[:required]
        end

        { type: "object", properties: properties, required: required }
      end

      # Execute tool calls and return results
      def execute_tool_calls(tool_calls, agent)
        tool_calls.map do |tc|
          execute_single_tool_call(tc, agent)
        end
      end

      # Execute a single tool call with timeout and error handling
      def execute_single_tool_call(tc, agent)
        tool_class = Ai::Tools::PlatformApiToolRegistry.find_tool(tc[:name])
        unless tool_class
          return { tool_call_id: tc[:id], content: JSON.generate({ success: false, error: "Unknown tool: #{tc[:name]}" }) }
        end

        result = Timeout.timeout(TOOL_CALL_TIMEOUT) do
          params = (tc[:arguments] || {}).deep_symbolize_keys
          params[:action] = tc[:name]
          tool_class.new(account: @team.account, agent: agent).execute(params: params)
        end

        { tool_call_id: tc[:id], content: JSON.generate(result) }
      rescue Timeout::Error
        { tool_call_id: tc[:id], content: JSON.generate({ success: false, error: "Tool call timed out after #{TOOL_CALL_TIMEOUT}s" }) }
      rescue StandardError => e
        { tool_call_id: tc[:id], content: JSON.generate({ success: false, error: e.message }) }
      end

      # build_tool_result_messages and extract_tool_calls provided by Ai::ToolCallExtraction
    end
  end
end

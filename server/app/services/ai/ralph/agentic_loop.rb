# frozen_string_literal: true

module Ai
  module Ralph
    class AgenticLoop
      MAX_TOOL_ROUNDS = 15

      def initialize(client:, provider_type:, account:, git_tool_executor: nil, mcp_tools: [])
        @client = client
        @provider_type = provider_type
        @account = account
        @git_executor = git_tool_executor
        @mcp_tools = mcp_tools
        @tool_calls_log = []
        @accumulated_content = []
      end

      # Execute an agentic tool-calling loop
      # @param messages [Array<Hash>] Initial messages (system + user)
      # @param options [Hash] Provider options (model, max_tokens, temperature, tools)
      # @return [Hash] { success:, content:, response:, metadata:, file_changes:, last_commit_sha:, tool_calls_log: }
      def execute(messages, options)
        messages = messages.dup
        last_response = nil
        model = options[:model]
        tools = options[:tools]
        call_opts = options.except(:model, :tools, :functions, :tool_choice)

        MAX_TOOL_ROUNDS.times do |round|
          response = if tools.present?
            @client.complete_with_tools(messages: messages, tools: tools, model: model, **call_opts)
          else
            @client.complete(messages: messages, model: model, **call_opts)
          end

          unless response.success?
            return build_error_result(response)
          end

          last_response = response

          # Accumulate any text content from this response
          @accumulated_content << response.content if response.content.present?

          # Check for tool calls
          if response.tool_calls.empty?
            return build_success_result(last_response)
          end

          # Append assistant message with tool calls (adapters handle format conversion)
          messages << build_assistant_tool_message(response)

          # Execute each tool call and collect results
          tool_results = response.tool_calls.map { |tc| execute_tool_call(tc) }

          # Build provider-specific result messages and append
          result_messages = build_tool_result_messages(tool_results)
          messages.concat(result_messages)
        end

        # Max rounds reached — make a final call without tools to get a summary
        final_response = @client.complete(messages: messages, model: model, **call_opts)

        if final_response.success?
          @accumulated_content << final_response.content if final_response.content.present?
          build_success_result(final_response)
        else
          build_error_result(final_response)
        end
      end

      private

      def execute_tool_call(tc)
        tool_name = tc[:name]
        arguments = tc[:arguments] || {}

        result = if GitToolDefinitions::GIT_TOOL_NAMES.include?(tool_name) && @git_executor
          @git_executor.execute(tool_name, arguments)
        else
          execute_mcp_tool(tool_name, arguments)
        end

        @tool_calls_log << {
          name: tool_name,
          arguments: arguments,
          result: result,
          timestamp: Time.current.iso8601
        }

        { tool_call_id: tc[:id], content: result.to_json }
      end

      def execute_mcp_tool(tool_name, arguments)
        mcp_tool = @mcp_tools.find { |t| t.name == tool_name }
        unless mcp_tool
          return { success: false, error: "Unknown tool: #{tool_name}" }
        end

        ::Mcp::SyncExecutionService.new(
          server: mcp_tool.mcp_server,
          tool: mcp_tool,
          parameters: arguments,
          user: nil,
          account: @account
        ).execute
      end

      # Build an assistant message containing tool calls for the conversation history.
      # The Ai::Llm adapters handle converting this normalized format to provider-specific
      # format (Anthropic tool_use content blocks vs OpenAI tool_calls array).
      def build_assistant_tool_message(response)
        tool_calls = response.tool_calls.map do |tc|
          { id: tc[:id], name: tc[:name], arguments: tc[:arguments] }
        end

        { role: "assistant", content: response.content, tool_calls: tool_calls }
      end

      # Build provider-specific tool result messages
      def build_tool_result_messages(results)
        case @provider_type
        when "anthropic"
          content_blocks = results.map do |r|
            { type: "tool_result", tool_use_id: r[:tool_call_id], content: r[:content] }
          end
          [{ role: "user", content: content_blocks }]
        else
          # OpenAI / Ollama format
          results.map do |r|
            { role: "tool", tool_call_id: r[:tool_call_id], content: r[:content] }
          end
        end
      end

      def build_success_result(last_response)
        content = @accumulated_content.join("\n\n")

        {
          success: true,
          content: content,
          response: last_response.raw_response,
          metadata: { usage: last_response.usage, cost: last_response.cost },
          file_changes: @git_executor&.file_changes || [],
          last_commit_sha: @git_executor&.last_commit_sha,
          tool_calls_log: @tool_calls_log
        }
      end

      def build_error_result(response)
        {
          success: false,
          error: response.content || "LLM call failed (finish_reason: #{response.finish_reason})",
          error_type: response.finish_reason,
          content: @accumulated_content.join("\n\n"),
          file_changes: @git_executor&.file_changes || [],
          last_commit_sha: @git_executor&.last_commit_sha,
          tool_calls_log: @tool_calls_log
        }
      end
    end
  end
end

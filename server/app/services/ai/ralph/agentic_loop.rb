# frozen_string_literal: true

module Ai
  module Ralph
    class AgenticLoop
      include Ai::ToolCallExtraction

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
        last_result = nil

        MAX_TOOL_ROUNDS.times do |round|
          result = @client.send_message(messages, options)

          unless result[:success]
            return build_error_result(result)
          end

          last_result = result
          response = result[:response]

          # Accumulate any text content from this response
          text = extract_text_content(response, @provider_type)
          @accumulated_content << text if text.present?

          # Check for tool calls
          tool_calls = extract_tool_calls(response, @provider_type)

          if tool_calls.empty?
            return build_success_result(last_result)
          end

          # Append assistant message with tool calls
          messages << build_assistant_tool_message(response, @provider_type)

          # Execute each tool call and collect results
          tool_results = tool_calls.map { |tc| execute_tool_call(tc) }

          # Build provider-specific result messages and append
          result_messages = build_tool_result_messages(tool_results, @provider_type)
          messages.concat(result_messages)
        end

        # Max rounds reached — make a final call without tools to get a summary
        final_options = options.except(:tools, :functions, :tool_choice)
        final_result = @client.send_message(messages, final_options)

        if final_result[:success]
          text = extract_text_content(final_result[:response], @provider_type)
          @accumulated_content << text if text.present?
          build_success_result(final_result)
        else
          build_error_result(final_result)
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

      def build_success_result(last_result)
        content = @accumulated_content.join("\n\n")

        {
          success: true,
          content: content,
          response: last_result[:response],
          metadata: last_result[:metadata],
          file_changes: @git_executor&.file_changes || [],
          last_commit_sha: @git_executor&.last_commit_sha,
          tool_calls_log: @tool_calls_log
        }
      end

      def build_error_result(result)
        {
          success: false,
          error: result[:error],
          error_type: result[:error_type],
          content: @accumulated_content.join("\n\n"),
          file_changes: @git_executor&.file_changes || [],
          last_commit_sha: @git_executor&.last_commit_sha,
          tool_calls_log: @tool_calls_log
        }
      end
    end
  end
end

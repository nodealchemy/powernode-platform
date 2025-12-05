# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for executing MCP tools asynchronously
  # This job handles the actual execution of MCP tools via the MCP protocol
  class McpToolExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id)
      log_info("Starting MCP tool execution", execution_id: execution_id)

      # Fetch execution details from backend API
      response = api_client.get("/api/v1/internal/mcp_tool_executions/#{execution_id}")

      unless response[:success]
        log_error("Failed to fetch execution details", nil, execution_id: execution_id)
        return
      end

      execution_data = response[:data][:mcp_tool_execution]
      tool = execution_data[:mcp_tool]
      server = tool[:mcp_server]

      # Update status to running
      api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
        status: 'running'
      })

      # Execute the tool via MCP protocol
      started_at = Time.current
      result = execute_mcp_tool(server, tool, execution_data[:parameters])
      duration_ms = ((Time.current - started_at) * 1000).to_i

      # Update execution with result
      if result[:success]
        api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
          status: 'completed',
          result: result[:output],
          execution_time_ms: duration_ms
        })

        log_info("MCP tool execution completed",
                 execution_id: execution_id,
                 tool_name: tool[:name],
                 duration_ms: duration_ms)
      else
        api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
          status: 'failed',
          error_message: result[:error],
          execution_time_ms: duration_ms
        })

        log_error("MCP tool execution failed", nil,
                  execution_id: execution_id,
                  tool_name: tool[:name],
                  error: result[:error])
      end
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP tool execution", e, execution_id: execution_id)
      raise
    rescue StandardError => e
      log_error("Unexpected error during MCP tool execution", e, execution_id: execution_id)
      raise
    end

    private

    def execute_mcp_tool(server, tool, parameters)
      case server[:connection_type]
      when 'stdio'
        execute_stdio_tool(server, tool, parameters)
      when 'websocket'
        execute_websocket_tool(server, tool, parameters)
      when 'http'
        execute_http_tool(server, tool, parameters)
      else
        { success: false, error: "Unknown connection type: #{server[:connection_type]}" }
      end
    end

    def execute_stdio_tool(server, tool, parameters)
      # Build the MCP tools/call request
      mcp_request = build_mcp_request('tools/call', {
        name: tool[:name],
        arguments: parameters
      })

      # Execute the command with the request piped to stdin
      command = server[:command]
      args = Array(server[:args])

      begin
        require 'open3'

        stdin_data = mcp_request.to_json
        stdout, stderr, status = Open3.capture3(
          server[:env] || {},
          command,
          *args,
          stdin_data: stdin_data
        )

        if status.success?
          response = parse_mcp_response(stdout)
          if response[:error]
            { success: false, error: response[:error][:message] }
          else
            { success: true, output: response[:result] }
          end
        else
          { success: false, error: "Process exited with code #{status.exitstatus}: #{stderr}" }
        end
      rescue Errno::ENOENT
        { success: false, error: "Command not found: #{command}" }
      rescue StandardError => e
        { success: false, error: "Execution error: #{e.message}" }
      end
    end

    def execute_websocket_tool(server, tool, parameters)
      # WebSocket tool execution would use websocket-client gem
      # For now, return a placeholder
      { success: false, error: "WebSocket tool execution not yet implemented" }
    end

    def execute_http_tool(server, tool, parameters)
      # HTTP tool execution via REST endpoint
      require 'net/http'

      begin
        uri = URI("#{server[:url]}/tools/call")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'

        mcp_request = build_mcp_request('tools/call', {
          name: tool[:name],
          arguments: parameters
        })
        request.body = mcp_request.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          result = JSON.parse(response.body)
          if result['error']
            { success: false, error: result['error']['message'] }
          else
            { success: true, output: result['result'] }
          end
        else
          { success: false, error: "HTTP error: #{response.code} - #{response.body}" }
        end
      rescue StandardError => e
        { success: false, error: "HTTP request failed: #{e.message}" }
      end
    end

    def build_mcp_request(method, params)
      {
        jsonrpc: '2.0',
        id: SecureRandom.uuid,
        method: method,
        params: params
      }
    end

    def parse_mcp_response(json_string)
      # MCP servers may output multiple JSON-RPC responses
      # We need to find the one matching our request
      lines = json_string.strip.split("\n")
      lines.reverse_each do |line|
        next if line.strip.empty?

        begin
          parsed = JSON.parse(line)
          return parsed.transform_keys(&:to_sym) if parsed['result'] || parsed['error']
        rescue JSON::ParserError
          next
        end
      end

      { error: { message: 'No valid MCP response received' } }
    end
  end
end

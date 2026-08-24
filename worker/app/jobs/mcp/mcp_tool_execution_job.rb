# frozen_string_literal: true

require_relative '../base_job'
require_relative '../../services/mcp/mcp_transport_client'

module Mcp
  # Job for executing MCP tools asynchronously.
  #
  # Orchestrates the execution lifecycle (fetch execution + tool/server,
  # flip status to running, report success/failure + telemetry) and delegates
  # the MCP protocol transport work (stdio / websocket / http + JSON-RPC
  # framing) to Mcp::McpTransportClient.
  class McpToolExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id)
      log_info("Starting MCP tool execution", execution_id: execution_id)

      # Fetch execution details from backend API. include_server_config=true
      # asks the backend to include the MCP server's env (secrets) in the nested
      # server payload — required by the stdio transport
      # (Mcp::McpTransportClient#execute_stdio_tool). The backend omits env by
      # default (see Api::V1::Internal::McpToolExecutionsController), so this
      # opt-in is what keeps stdio execution working.
      response = api_client.get(
        "/api/v1/internal/mcp_tool_executions/#{execution_id}",
        { include_server_config: true }
      )

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

    # Delegate the actual transport (stdio / websocket / http dispatch) to the
    # transport client. The job stays a thin orchestrator.
    def execute_mcp_tool(server, tool, parameters)
      mcp_transport_client.execute(server, tool, parameters)
    end

    # Thin delegators retained so the transport seam stays addressable from the
    # job; all real work lives in Mcp::McpTransportClient.
    def execute_websocket_tool(server, tool, parameters)
      mcp_transport_client.execute_websocket_tool(server, tool, parameters)
    end

    def build_mcp_request(method, params)
      mcp_transport_client.build_mcp_request(method, params)
    end

    def parse_mcp_response(json_string)
      mcp_transport_client.parse_mcp_response(json_string)
    end

    def mcp_transport_client
      @mcp_transport_client ||= Mcp::McpTransportClient.new
    end
  end
end

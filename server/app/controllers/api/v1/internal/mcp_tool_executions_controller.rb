# frozen_string_literal: true

class Api::V1::Internal::McpToolExecutionsController < Api::V1::Internal::InternalBaseController
  include Api::V1::Internal::WorkerTenancy

  # Internal API endpoints for MCP tool execution tracking
  # These endpoints are called by background workers only

  # GET /api/v1/internal/mcp_tool_executions/:id
  def show
    execution = execution_scope.includes(mcp_tool: :mcp_server).find(params[:id])

    render_success({
      mcp_tool_execution: serialize_execution(
        execution, include_server_config: server_config_requested?
      )
    })
  rescue ActiveRecord::RecordNotFound
    render_error("MCP tool execution not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to get MCP tool execution: #{e.message}"
    render_error("Failed to get MCP tool execution", status: :internal_server_error)
  end

  # PATCH /api/v1/internal/mcp_tool_executions/:id
  def update
    execution = execution_scope.find(params[:id])

    case params[:status]
    when "running"
      execution.start!
    when "completed"
      execution.complete!(params[:result] || {})
    when "failed"
      execution.fail!(params[:error] || "Execution failed")
    when "cancelled"
      execution.cancel!
    else
      execution.update!(execution_params)
    end

    # Broadcast the update
    broadcast_execution_update(execution)

    render_success({
      mcp_tool_execution: serialize_execution(execution),
      message: "Execution status updated successfully"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("MCP tool execution not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update MCP tool execution: #{e.message}"
    render_error("Failed to update MCP tool execution", status: :internal_server_error)
  end

  private

  def execution_params
    params.permit(
      :status,
      :error_message,
      :execution_time_ms,
      :started_at,
      :completed_at,
      result: {}
    )
  end

  def serialize_execution(execution, include_server_config: false)
    {
      id: execution.id,
      status: execution.status,
      parameters: execution.parameters,
      result: execution.result,
      error_message: execution.error_message,
      execution_time_ms: execution.execution_time_ms,
      started_at: execution.started_at,
      completed_at: execution.completed_at,
      created_at: execution.created_at,
      user_id: execution.user_id,
      mcp_tool: {
        id: execution.mcp_tool.id,
        name: execution.mcp_tool.name,
        description: execution.mcp_tool.description,
        input_schema: execution.mcp_tool.input_schema,
        mcp_server: serialize_nested_server(
          execution.mcp_tool.mcp_server, include_server_config: include_server_config
        )
      }
    }
  end

  # An execution record does not require the server's secrets to be meaningful,
  # so `env` (API keys, tokens, connection secrets) is OMITTED by default and
  # emitted only when the caller explicitly asks and is entitled to it. The one
  # legitimate consumer, the worker's stdio transport
  # (Mcp::McpTransportClient#execute_stdio_tool), requests it via
  # `?include_server_config=true`; every other reader gets the default,
  # secret-free representation. Defence in depth BEHIND the tenancy scope, not
  # in place of it.
  def serialize_nested_server(server, include_server_config: false)
    nested = {
      id: server.id,
      name: server.name,
      status: server.status,
      connection_type: server.connection_type,
      command: server.command,
      args: server.args,
      url: server.url
    }
    nested[:env] = server.env if include_server_config
    nested
  end

  def server_config_requested?
    ActiveModel::Type::Boolean.new.cast(params[:include_server_config])
  end

  # Tenancy scope: `mcp_tool_executions` has no `account_id` column, so tenancy
  # is joined through mcp_tool -> mcp_server. A bare
  # `McpToolExecution.find` disclosed any tenant's execution (and, before the
  # gate above, its server's env) by enumerable id. `mcp_servers.account_id` is
  # NOT NULL, so a nil worker account_id (fail-closed) catches no rows.
  # Cross-account id -> 404, never 403. See Api::V1::Internal::WorkerTenancy.
  def execution_scope
    McpToolExecution
      .joins(mcp_tool: :mcp_server)
      .where(mcp_servers: { account_id: worker_account_id })
  end

  def broadcast_execution_update(execution)
    # Broadcast to execution-specific channel
    ActionCable.server.broadcast(
      "mcp_tool_execution_#{execution.id}",
      {
        type: "execution_update",
        execution_id: execution.id,
        status: execution.status,
        result: execution.result,
        error_message: execution.error_message,
        execution_time_ms: execution.execution_time_ms,
        completed_at: execution.completed_at,
        timestamp: Time.current.iso8601
      }
    )

    # Also broadcast to the tool channel for dashboard updates
    ActionCable.server.broadcast(
      "mcp_tool_#{execution.mcp_tool_id}",
      {
        type: "execution_complete",
        execution_id: execution.id,
        status: execution.status,
        timestamp: Time.current.iso8601
      }
    )
  end
end

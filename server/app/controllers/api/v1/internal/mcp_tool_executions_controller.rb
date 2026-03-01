# frozen_string_literal: true

class Api::V1::Internal::McpToolExecutionsController < Api::V1::Internal::InternalBaseController
  # Internal API endpoints for MCP tool execution tracking
  # These endpoints are called by background workers only

  # GET /api/v1/internal/mcp_tool_executions/:id
  def show
    execution = McpToolExecution.includes(mcp_tool: :mcp_server).find(params[:id])

    render_success({
      mcp_tool_execution: serialize_execution(execution)
    })
  rescue ActiveRecord::RecordNotFound
    render_error("MCP tool execution not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to get MCP tool execution: #{e.message}"
    render_error("Failed to get MCP tool execution", status: :internal_server_error)
  end

  # PATCH /api/v1/internal/mcp_tool_executions/:id
  def update
    execution = McpToolExecution.find(params[:id])

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

  def serialize_execution(execution)
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
        mcp_server: {
          id: execution.mcp_tool.mcp_server.id,
          name: execution.mcp_tool.mcp_server.name,
          status: execution.mcp_tool.mcp_server.status,
          connection_type: execution.mcp_tool.mcp_server.connection_type,
          command: execution.mcp_tool.mcp_server.command,
          args: execution.mcp_tool.mcp_server.args,
          url: execution.mcp_tool.mcp_server.url,
          env: execution.mcp_tool.mcp_server.env
        }
      }
    }
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

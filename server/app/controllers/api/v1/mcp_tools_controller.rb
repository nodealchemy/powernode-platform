# frozen_string_literal: true

class Api::V1::McpToolsController < ApplicationController
  include AuditLogging

  before_action :authenticate_request
  before_action :set_mcp_server
  before_action :require_read_permission, only: [:index, :show, :stats]
  before_action :require_execute_permission, only: [:execute]
  before_action :set_mcp_tool, only: [:show, :execute, :stats]

  # GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools
  def index
    tools = @mcp_server.mcp_tools.order(name: :asc)

    # Filter by enabled status
    tools = tools.where(enabled: true) if params[:enabled] == 'true'
    tools = tools.where(enabled: false) if params[:enabled] == 'false'

    render_success({
      mcp_tools: tools.map { |tool| serialize_mcp_tool(tool) },
      mcp_server: {
        id: @mcp_server.id,
        name: @mcp_server.name,
        status: @mcp_server.status
      },
      meta: {
        total: tools.count,
        enabled_count: @mcp_server.mcp_tools.where(enabled: true).count,
        disabled_count: @mcp_server.mcp_tools.where(enabled: false).count
      }
    })

    log_audit_event('mcp.tools.read', @mcp_server)
  rescue => e
    Rails.logger.error "Failed to list MCP tools: #{e.message}"
    render_error('Failed to list MCP tools', status: :internal_server_error)
  end

  # GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id
  def show
    render_success({
      mcp_tool: serialize_mcp_tool(@mcp_tool, include_details: true),
      mcp_server: {
        id: @mcp_server.id,
        name: @mcp_server.name,
        status: @mcp_server.status
      }
    })

    log_audit_event('mcp.tools.read', @mcp_tool)
  rescue => e
    Rails.logger.error "Failed to get MCP tool: #{e.message}"
    render_error('Failed to get MCP tool', status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id/execute
  def execute
    unless @mcp_tool.enabled
      return render_error('Tool is disabled', status: :unprocessable_content)
    end

    unless @mcp_server.status == 'connected'
      return render_error('MCP server is not connected', status: :unprocessable_content)
    end

    parameters = params[:parameters] || {}

    # Validate parameters against input schema
    validation_result = @mcp_tool.validate_parameters(parameters)
    unless validation_result[:valid]
      return render_error(
        "Invalid parameters: #{validation_result[:errors].join(', ')}",
        status: :unprocessable_content
      )
    end

    # Execute the tool (asynchronously)
    begin
      execution = @mcp_tool.execute(user: current_user, account: current_user.account, parameters: parameters)

      render_success({
        execution: serialize_execution(execution),
        mcp_tool: {
          id: @mcp_tool.id,
          name: @mcp_tool.name
        },
        mcp_server: {
          id: @mcp_server.id,
          name: @mcp_server.name
        },
        message: 'Tool execution started'
      }, status: :accepted)

      log_audit_event('mcp.tools.execute', @mcp_tool, execution_id: execution.id)
    rescue StandardError => e
      Rails.logger.error "Failed to execute MCP tool: #{e.message}"
      render_error("Failed to execute tool: #{e.message}", status: :internal_server_error)
    end
  end

  # GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:id/stats
  def stats
    # Calculate statistics for this tool
    executions = @mcp_tool.mcp_tool_executions
    recent_executions = executions.where('created_at >= ?', 30.days.ago)

    success_count = executions.where(status: 'completed').count
    failure_count = executions.where(status: 'failed').count
    pending_count = executions.where(status: 'pending').count
    running_count = executions.where(status: 'running').count

    # Calculate average duration for completed executions
    completed = executions.where(status: ['completed', 'failed']).where.not(duration_ms: nil)
    avg_duration = completed.any? ? completed.average(:duration_ms)&.round(2) : 0

    render_success({
      mcp_tool_id: @mcp_tool.id,
      stats: {
        total_executions: executions.count,
        success_count: success_count,
        failure_count: failure_count,
        pending_count: pending_count,
        running_count: running_count,
        success_rate: executions.count > 0 ? ((success_count.to_f / executions.count) * 100).round(2) : 0,
        average_duration_ms: avg_duration,
        recent_30_days: recent_executions.count,
        last_execution_at: executions.maximum(:created_at),
        first_execution_at: executions.minimum(:created_at)
      },
      mcp_server: {
        id: @mcp_server.id,
        name: @mcp_server.name
      }
    })

    log_audit_event('mcp.tools.read', @mcp_tool)
  rescue => e
    Rails.logger.error "Failed to get MCP tool stats: #{e.message}"
    render_error('Failed to get tool stats', status: :internal_server_error)
  end

  private

  def set_mcp_server
    @mcp_server = current_user.account.mcp_servers.find(params[:mcp_server_id])
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  end

  def set_mcp_tool
    @mcp_tool = @mcp_server.mcp_tools.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('MCP tool not found', status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?('mcp.tools.read')
      render_error('Insufficient permissions to view MCP tools', status: :forbidden)
    end
  end

  def require_execute_permission
    unless current_user.has_permission?('mcp.tools.execute')
      render_error('Insufficient permissions to execute MCP tools', status: :forbidden)
    end
  end

  def serialize_mcp_tool(tool, include_details: false)
    result = {
      id: tool.id,
      name: tool.name,
      description: tool.description,
      enabled: tool.enabled,
      execution_count: tool.execution_count,
      last_executed_at: tool.last_executed_at,
      created_at: tool.created_at,
      updated_at: tool.updated_at
    }

    if include_details
      result.merge!({
        input_schema: tool.input_schema,
        output_schema: tool.output_schema,
        config: tool.config
      })
    end

    result
  end

  def serialize_execution(execution)
    {
      id: execution.id,
      status: execution.status,
      parameters: execution.parameters,
      result: execution.result,
      error_message: execution.error_message,
      duration_ms: execution.duration_ms,
      created_at: execution.created_at,
      started_at: execution.started_at,
      completed_at: execution.completed_at
    }
  end
end

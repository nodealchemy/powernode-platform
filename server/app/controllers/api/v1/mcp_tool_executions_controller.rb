# frozen_string_literal: true

class Api::V1::McpToolExecutionsController < ApplicationController
  include AuditLogging

  before_action :authenticate_request
  before_action :set_mcp_server
  before_action :set_mcp_tool
  before_action :require_read_permission, only: [ :index, :show ]
  before_action :require_write_permission, only: [ :cancel ]
  before_action :set_execution, only: [ :show, :cancel ]

  # GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions
  def index
    executions = @mcp_tool.mcp_tool_executions
                         .includes(:user)
                         .order(created_at: :desc)

    # Filter by status if provided
    executions = executions.where(status: params[:status]) if params[:status].present?

    # Filter by user if admin and user_id provided
    if params[:user_id].present? && current_user.has_permission?("admin.user.read")
      executions = executions.where(user_id: params[:user_id])
    elsif !current_user.has_permission?("admin.user.read")
      # Non-admin users can only see their own executions
      executions = executions.where(user_id: current_user.id)
    end

    # Time filter
    if params[:since].present?
      begin
        since_time = Time.parse(params[:since])
        executions = executions.where("created_at >= ?", since_time)
      rescue ArgumentError
        # Invalid time format, ignore filter
      end
    end

    # Pagination using Kaminari
    page = params[:page] || 1
    per_page = [ params[:per_page]&.to_i || 20, 100 ].min # Default 20, cap at 100

    paginated_executions = executions.page(page).per(per_page)

    render_success({
      executions: paginated_executions.map { |exec| serialize_execution(exec) },
      mcp_tool: {
        id: @mcp_tool.id,
        name: @mcp_tool.name
      },
      mcp_server: {
        id: @mcp_server.id,
        name: @mcp_server.name
      },
      pagination: {
        current_page: paginated_executions.current_page,
        per_page: paginated_executions.limit_value,
        total_pages: paginated_executions.total_pages,
        total_count: paginated_executions.total_count
      },
      meta: {
        pending_count: executions.where(status: "pending").count,
        running_count: executions.where(status: "running").count,
        success_count: executions.where(status: "success").count,
        failed_count: executions.where(status: "failed").count,
        cancelled_count: executions.where(status: "cancelled").count
      }
    })

    log_audit_event("mcp.executions.read", @mcp_tool)
  rescue => e
    Rails.logger.error "Failed to list MCP tool executions: #{e.message}"
    render_error("Failed to list tool executions", status: :internal_server_error)
  end

  # GET /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions/:id
  def show
    # Check if user can view this execution
    unless can_view_execution?(@execution)
      return render_error("Insufficient permissions to view this execution", status: :forbidden)
    end

    render_success({
      execution: serialize_execution(@execution, include_details: true),
      mcp_tool: {
        id: @mcp_tool.id,
        name: @mcp_tool.name,
        description: @mcp_tool.description
      },
      mcp_server: {
        id: @mcp_server.id,
        name: @mcp_server.name,
        status: @mcp_server.status
      }
    })

    log_audit_event("mcp.executions.read", @execution)
  rescue => e
    Rails.logger.error "Failed to get MCP tool execution: #{e.message}"
    render_error("Failed to get tool execution", status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers/:mcp_server_id/mcp_tools/:mcp_tool_id/executions/:id/cancel
  def cancel
    # Check if user can cancel this execution
    unless can_modify_execution?(@execution)
      return render_error("Insufficient permissions to cancel this execution", status: :forbidden)
    end

    # Can only cancel pending or running executions
    unless [ "pending", "running" ].include?(@execution.status)
      return render_error(
        "Cannot cancel execution with status '#{@execution.status}'",
        status: :unprocessable_content
      )
    end

    begin
      if @execution.cancel!
        render_success({
          execution: serialize_execution(@execution),
          message: "Execution cancelled successfully"
        })

        log_audit_event("mcp.executions.cancel", @execution)
      else
        render_error("Failed to cancel execution", status: :unprocessable_content)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to cancel execution: #{e.message}"
      render_error("Failed to cancel execution: #{e.message}", status: :internal_server_error)
    end
  end

  private

  def set_mcp_server
    @mcp_server = current_user.account.mcp_servers.find(params[:mcp_server_id])
  rescue ActiveRecord::RecordNotFound
    render_error("MCP server not found", status: :not_found)
  end

  def set_mcp_tool
    @mcp_tool = @mcp_server.mcp_tools.find(params[:mcp_tool_id])
  rescue ActiveRecord::RecordNotFound
    render_error("MCP tool not found", status: :not_found)
  end

  def set_execution
    @execution = @mcp_tool.mcp_tool_executions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Tool execution not found", status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?("mcp.executions.read")
      render_error("Insufficient permissions to view MCP tool executions", status: :forbidden)
    end
  end

  def require_write_permission
    unless current_user.has_permission?("mcp.executions.write")
      render_error("Insufficient permissions to manage MCP tool executions", status: :forbidden)
    end
  end

  def can_view_execution?(execution)
    # Admin users can view all executions
    return true if current_user.has_permission?("admin.user.read")

    # Regular users can only view their own executions
    execution.user_id == current_user.id
  end

  def can_modify_execution?(execution)
    # Admin users can modify all executions
    return true if current_user.has_permission?("admin.user.read")

    # Regular users can only modify their own executions
    execution.user_id == current_user.id
  end

  def serialize_execution(execution, include_details: false)
    result = {
      id: execution.id,
      status: execution.status,
      user_id: execution.user_id,
      user_name: execution.user&.name,
      duration_ms: execution.duration_ms,
      created_at: execution.created_at,
      started_at: execution.started_at,
      completed_at: execution.completed_at
    }

    if include_details
      result.merge!({
        parameters: execution.parameters,
        result: execution.result,
        error_message: execution.error_message,
        execution_time_ms: execution.execution_time_ms
      })
    end

    result
  end
end

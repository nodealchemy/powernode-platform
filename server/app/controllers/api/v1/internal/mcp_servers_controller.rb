# frozen_string_literal: true

class Api::V1::Internal::McpServersController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  # Internal API endpoints for MCP server management
  # These endpoints are called by background workers only

  # GET /api/v1/internal/mcp_servers
  def index
    servers = McpServer.all

    # Filter by status if provided
    servers = servers.where(status: params[:status]) if params[:status].present?

    render_success({
      mcp_servers: servers.map { |server| serialize_server(server) }
    })
  rescue StandardError => e
    Rails.logger.error "Failed to list MCP servers: #{e.message}"
    render_error('Failed to list MCP servers', status: :internal_server_error)
  end

  # GET /api/v1/internal/mcp_servers/:id
  def show
    server = McpServer.find(params[:id])

    render_success({
      mcp_server: serialize_server(server, include_config: true)
    })
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to get MCP server: #{e.message}"
    render_error('Failed to get MCP server', status: :internal_server_error)
  end

  # PATCH /api/v1/internal/mcp_servers/:id
  def update
    server = McpServer.find(params[:id])
    server.update!(server_params)

    # Broadcast status change if status was updated
    if server.saved_change_to_status?
      broadcast_status_update(server)
    end

    render_success({
      mcp_server: serialize_server(server),
      message: 'MCP server updated successfully'
    })
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update MCP server: #{e.message}"
    render_error('Failed to update MCP server', status: :internal_server_error)
  end

  # POST /api/v1/internal/mcp_servers/:id/health_result
  def health_result
    server = McpServer.find(params[:id])

    server.update!(
      last_health_check: Time.current,
      status: params[:healthy] ? server.status : 'error',
      capabilities: server.capabilities.merge(
        'last_latency_ms' => params[:latency_ms],
        'last_health_check_at' => Time.current.iso8601
      )
    )

    # Broadcast health update
    broadcast_health_update(server, params[:healthy], params[:latency_ms])

    render_success({
      updated: true,
      status: server.status
    })
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update health result: #{e.message}"
    render_error('Failed to update health result', status: :internal_server_error)
  end

  # POST /api/v1/internal/mcp_servers/:id/register_tools
  def register_tools
    server = McpServer.find(params[:id])
    tools_registered = 0

    Array(params[:tools]).each do |tool_data|
      tool = server.mcp_tools.find_or_initialize_by(name: tool_data[:name])
      tool.description = tool_data[:description]
      tool.input_schema = tool_data[:input_schema] || {}
      tool.enabled = tool_data[:enabled].nil? ? true : tool_data[:enabled]
      tool.permission_level = tool_data[:permission_level] || 'account'

      if tool.save
        tools_registered += 1
      else
        Rails.logger.warn "Failed to register tool #{tool_data[:name]}: #{tool.errors.full_messages.join(', ')}"
      end
    end

    # Broadcast tools update
    ActionCable.server.broadcast(
      "mcp_server_#{server.id}",
      {
        type: 'tools_updated',
        server_id: server.id,
        tools_count: server.mcp_tools.count,
        timestamp: Time.current.iso8601
      }
    )

    render_success({
      tools_registered: tools_registered,
      total_tools: server.mcp_tools.count
    })
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to register tools: #{e.message}"
    render_error('Failed to register tools', status: :internal_server_error)
  end

  private

  def server_params
    params.permit(
      :status,
      :last_error,
      :last_connected_at,
      :last_health_check,
      capabilities: {}
    )
  end

  def serialize_server(server, include_config: false)
    result = {
      id: server.id,
      name: server.name,
      status: server.status,
      connection_type: server.connection_type,
      command: server.command,
      args: server.args,
      url: server.url,
      capabilities: server.capabilities,
      last_connected_at: server.last_connected_at,
      last_health_check: server.last_health_check,
      last_error: server.last_error,
      account_id: server.account_id
    }

    if include_config
      result[:env] = server.env
      result[:config] = server.config
    end

    result
  end

  def broadcast_status_update(server)
    ActionCable.server.broadcast(
      "mcp_server_#{server.id}",
      {
        type: 'status_change',
        server_id: server.id,
        status: server.status,
        timestamp: Time.current.iso8601
      }
    )

    # Also broadcast to account channel for dashboard updates
    ActionCable.server.broadcast(
      "account_#{server.account_id}_mcp",
      {
        type: 'server_status_change',
        server_id: server.id,
        server_name: server.name,
        status: server.status,
        timestamp: Time.current.iso8601
      }
    )
  end

  def broadcast_health_update(server, healthy, latency_ms)
    ActionCable.server.broadcast(
      "mcp_server_#{server.id}",
      {
        type: 'health_check',
        server_id: server.id,
        healthy: healthy,
        latency_ms: latency_ms,
        timestamp: Time.current.iso8601
      }
    )
  end

  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last

    unless token.present?
      render_error('Service token required', status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first

      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render_error('Invalid service token', status: :unauthorized)
        return
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid service token', status: :unauthorized)
    end
  end
end

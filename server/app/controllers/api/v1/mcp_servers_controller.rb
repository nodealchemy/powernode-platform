# frozen_string_literal: true

class Api::V1::McpServersController < ApplicationController
  include ApiResponse
  include AuditLogging

  before_action :authenticate_request
  before_action :require_read_permission, only: [:index, :show, :health_check, :for_workflow_builder]
  before_action :require_write_permission, only: [:create, :update, :destroy, :connect, :disconnect, :discover_tools]
  before_action :set_mcp_server, only: [:show, :update, :destroy, :connect, :disconnect, :health_check, :discover_tools]

  # GET /api/v1/mcp_servers
  def index
    servers = current_user.account.mcp_servers.includes(:mcp_tools).order(created_at: :desc)

    # Filter by status if provided
    servers = servers.where(status: params[:status]) if params[:status].present?

    # Filter by connection_type if provided
    servers = servers.where(connection_type: params[:connection_type]) if params[:connection_type].present?

    render_success({
      mcp_servers: servers.map { |server| serialize_mcp_server(server) },
      meta: {
        total: servers.count,
        connected_count: current_user.account.mcp_servers.where(status: 'connected').count,
        disconnected_count: current_user.account.mcp_servers.where(status: 'disconnected').count,
        error_count: current_user.account.mcp_servers.where(status: 'error').count
      }
    })

    log_audit_event('mcp.servers.read', current_user.account)
  rescue => e
    Rails.logger.error "Failed to list MCP servers: #{e.message}"
    render_error('Failed to list MCP servers', status: :internal_server_error)
  end

  # GET /api/v1/mcp_servers/:id
  def show
    render_success({
      mcp_server: serialize_mcp_server(@mcp_server, include_tools: true)
    })

    log_audit_event('mcp.servers.read', @mcp_server)
  rescue => e
    Rails.logger.error "Failed to get MCP server: #{e.message}"
    render_error('Failed to get MCP server', status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers
  def create
    server = current_user.account.mcp_servers.new(mcp_server_params)

    if server.save
      render_success({
        mcp_server: serialize_mcp_server(server),
        message: 'MCP server created successfully'
      }, status: :created)

      log_audit_event('mcp.servers.create', server)
    else
      render_validation_error(server.errors)
    end
  rescue => e
    Rails.logger.error "Failed to create MCP server: #{e.message}"
    render_error('Failed to create MCP server', status: :internal_server_error)
  end

  # PATCH/PUT /api/v1/mcp_servers/:id
  def update
    if @mcp_server.update(mcp_server_params)
      render_success({
        mcp_server: serialize_mcp_server(@mcp_server),
        message: 'MCP server updated successfully'
      })

      log_audit_event('mcp.servers.update', @mcp_server)
    else
      render_validation_error(@mcp_server.errors)
    end
  rescue => e
    Rails.logger.error "Failed to update MCP server: #{e.message}"
    render_error('Failed to update MCP server', status: :internal_server_error)
  end

  # DELETE /api/v1/mcp_servers/:id
  def destroy
    @mcp_server.destroy!

    render_success({
      message: 'MCP server deleted successfully'
    })

    log_audit_event('mcp.servers.delete', @mcp_server)
  rescue => e
    Rails.logger.error "Failed to delete MCP server: #{e.message}"
    render_error('Failed to delete MCP server', status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers/:id/connect
  def connect
    begin
      @mcp_server.connect!

      render_success({
        mcp_server: serialize_mcp_server(@mcp_server, include_tools: true),
        message: 'MCP server connected successfully'
      })

      log_audit_event('mcp.servers.connect', @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to connect to MCP server: #{e.message}"
      @mcp_server.update(status: 'error', last_error: e.message)
      render_error("Failed to connect: #{e.message}", status: :unprocessable_content)
    end
  end

  # POST /api/v1/mcp_servers/:id/disconnect
  def disconnect
    begin
      @mcp_server.disconnect!

      render_success({
        mcp_server: serialize_mcp_server(@mcp_server),
        message: 'MCP server disconnected successfully'
      })

      log_audit_event('mcp.servers.disconnect', @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to disconnect from MCP server: #{e.message}"
      render_error("Failed to disconnect: #{e.message}", status: :unprocessable_content)
    end
  end

  # POST /api/v1/mcp_servers/:id/health_check
  def health_check
    begin
      is_healthy = @mcp_server.health_check

      render_success({
        mcp_server_id: @mcp_server.id,
        healthy: is_healthy,
        status: @mcp_server.status,
        last_connected_at: @mcp_server.last_connected_at,
        last_error: @mcp_server.last_error,
        checked_at: Time.current
      })

      log_audit_event('mcp.servers.health_check', @mcp_server)
    rescue => e
      Rails.logger.error "Health check failed: #{e.message}"
      render_error("Health check failed: #{e.message}", status: :internal_server_error)
    end
  end

  # POST /api/v1/mcp_servers/:id/discover_tools
  def discover_tools
    begin
      tools = @mcp_server.discover_tools

      render_success({
        mcp_server_id: @mcp_server.id,
        tools_discovered: tools.count,
        tools: tools.map { |tool| serialize_mcp_tool(tool) },
        message: "Discovered #{tools.count} tools"
      })

      log_audit_event('mcp.servers.discover_tools', @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to discover tools: #{e.message}"
      render_error("Failed to discover tools: #{e.message}", status: :unprocessable_content)
    end
  end

  # GET /api/v1/mcp_servers/for_workflow_builder
  # Returns connected MCP servers with their tools, resources, and prompts for the workflow builder
  def for_workflow_builder
    servers = current_user.account.mcp_servers
                          .includes(:mcp_tools)
                          .where(status: 'connected')
                          .order(:name)

    render_success({
      mcp_servers: servers.map { |server| serialize_for_workflow_builder(server) },
      meta: {
        total_servers: servers.count,
        total_tools: servers.sum { |s| s.mcp_tools.enabled.count }
      }
    })

    log_audit_event('mcp.servers.workflow_builder_read', current_user.account)
  rescue => e
    Rails.logger.error "Failed to load MCP servers for workflow builder: #{e.message}"
    render_error('Failed to load MCP servers', status: :internal_server_error)
  end

  private

  def set_mcp_server
    @mcp_server = current_user.account.mcp_servers.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error('MCP server not found', status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?('mcp.servers.read')
      render_error('Insufficient permissions to view MCP servers', status: :forbidden)
    end
  end

  def require_write_permission
    unless current_user.has_permission?('mcp.servers.write')
      render_error('Insufficient permissions to manage MCP servers', status: :forbidden)
    end
  end

  def mcp_server_params
    params.require(:mcp_server).permit(
      :name,
      :description,
      :connection_type,
      :command,
      :args,
      :url,
      :api_key,
      config: {}
    )
  end

  def serialize_mcp_server(server, include_tools: false)
    result = {
      id: server.id,
      name: server.name,
      description: server.description,
      connection_type: server.connection_type,
      status: server.status,
      command: server.command,
      args: server.args,
      url: server.url,
      last_connected_at: server.last_connected_at,
      last_error: server.last_error,
      config: server.config,
      created_at: server.created_at,
      updated_at: server.updated_at
    }

    if include_tools
      result[:tools] = server.mcp_tools.map { |tool| serialize_mcp_tool(tool) }
      result[:tools_count] = server.mcp_tools.count
    else
      result[:tools_count] = server.mcp_tools.count
    end

    result
  end

  def serialize_mcp_tool(tool)
    {
      id: tool.id,
      name: tool.name,
      description: tool.description,
      input_schema: tool.input_schema,
      enabled: tool.enabled,
      execution_count: tool.execution_count,
      created_at: tool.created_at
    }
  end

  def serialize_for_workflow_builder(server)
    {
      id: server.id,
      name: server.name,
      description: server.description,
      status: server.status,
      connection_type: server.connection_type,
      capabilities: server.capabilities,
      tools: server.mcp_tools.enabled.map do |tool|
        {
          id: tool.id,
          name: tool.name,
          description: tool.description,
          input_schema: tool.input_schema,
          permission_level: tool.permission_level
        }
      end,
      # Resources and prompts would be fetched from capabilities
      resources: extract_resources_from_capabilities(server),
      prompts: extract_prompts_from_capabilities(server)
    }
  end

  def extract_resources_from_capabilities(server)
    capabilities = server.capabilities || {}
    resources = capabilities['resources'] || capabilities[:resources] || []
    resources.map do |resource|
      {
        uri: resource['uri'] || resource[:uri],
        name: resource['name'] || resource[:name],
        description: resource['description'] || resource[:description],
        mime_type: resource['mimeType'] || resource[:mimeType]
      }
    end
  end

  def extract_prompts_from_capabilities(server)
    capabilities = server.capabilities || {}
    prompts = capabilities['prompts'] || capabilities[:prompts] || []
    prompts.map do |prompt|
      {
        name: prompt['name'] || prompt[:name],
        description: prompt['description'] || prompt[:description],
        arguments: prompt['arguments'] || prompt[:arguments] || []
      }
    end
  end
end

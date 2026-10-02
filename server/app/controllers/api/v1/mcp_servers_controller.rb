# frozen_string_literal: true

class Api::V1::McpServersController < ApplicationController
  include AuditLogging
  include Api::V1::McpServerConfigSerialization
  include Api::V1::McpServerNativeExecutionActions
  include Api::V1::McpServerSecurityActions

  before_action :authenticate_request
  # update_security answers with the serialized server (config included), so it needs the read
  # permission as well as its own (IMP-cdda895b07a8).
  before_action :require_read_permission, only: [ :index, :show, :health_check, :update_security ]
  before_action :require_write_permission, only: [ :create, :update, :destroy, :connect, :disconnect, :discover_tools ]
  # IMP-2c760325c102 — its own permission, deliberately not mcp.servers.write
  # (see config/permissions.rb): the hatch is approved by an operator, in a
  # separate request from whoever created or edited the server.
  before_action :require_native_execution_permission, only: [ :approve_native_execution, :revoke_native_execution ]
  # IMP-cdda895b07a8 — likewise its own permission (mcp.servers.security_manage).
  before_action :require_security_manage_permission, only: [ :update_security ]
  before_action :set_mcp_server, only: [ :show, :update, :destroy, :connect, :disconnect, :health_check, :discover_tools,
                                         :approve_native_execution, :revoke_native_execution, :update_security ]
  before_action :validate_config_keys, only: [ :create, :update ]

  # GET /api/v1/mcp_servers
  def index
    servers = current_user.account.mcp_servers.includes(:mcp_tools).order(created_at: :desc)

    # Filter by status if provided
    servers = servers.where(status: params[:status]) if params[:status].present?

    # Filter by connection_type if provided
    servers = servers.where(connection_type: params[:connection_type]) if params[:connection_type].present?

    # Use single aggregation query to avoid N+1
    status_counts = current_user.account.mcp_servers.group(:status).count

    render_success({
      mcp_servers: servers.map { |server| serialize_mcp_server(server) },
      meta: {
        total: servers.count,
        connected_count: status_counts["connected"] || 0,
        disconnected_count: status_counts["disconnected"] || 0,
        error_count: status_counts["error"] || 0
      }
    })

    log_audit_event("mcp.servers.read", current_user.account)
  rescue StandardError => e
    Rails.logger.error "Failed to list MCP servers: #{e.message}"
    render_error("Failed to list MCP servers", status: :internal_server_error)
  end

  # GET /api/v1/mcp_servers/:id
  def show
    render_success({
      mcp_server: serialize_mcp_server(@mcp_server, include_tools: true)
    })

    log_audit_event("mcp.servers.read", @mcp_server)
  rescue StandardError => e
    Rails.logger.error "Failed to get MCP server: #{e.message}"
    render_error("Failed to get MCP server", status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers
  def create
    server = current_user.account.mcp_servers.new(mcp_server_params)

    if server.save
      render_success({
        mcp_server: serialize_mcp_server(server),
        message: "MCP server created successfully"
      }, status: :created)

      log_audit_event("mcp.servers.create", server)
    else
      render_validation_error(server.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to create MCP server: #{e.message}"
    render_error("Failed to create MCP server", status: :internal_server_error)
  end

  # PATCH/PUT /api/v1/mcp_servers/:id
  def update
    if @mcp_server.update(mcp_server_params)
      render_success({
        mcp_server: serialize_mcp_server(@mcp_server),
        message: "MCP server updated successfully"
      })

      log_audit_event("mcp.servers.update", @mcp_server)
      # IMP-2c760325c102 — the model drops a native-execution approval when
      # the command line it was granted for changes; that is a revoke and
      # is audited as one, with its reason.
      if @mcp_server.native_execution_cleared_by_change?
        log_audit_event("mcp.servers.native_execution_revoke", @mcp_server,
                        severity: "high", risk_level: "high", metadata: { reason: "command_changed" })
      end
    else
      render_validation_error(@mcp_server.errors)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update MCP server: #{e.message}"
    render_error("Failed to update MCP server", status: :internal_server_error)
  end

  # POST/DELETE /api/v1/mcp_servers/:id/native_execution — see
  # Api::V1::McpServerNativeExecutionActions (IMP-2c760325c102).

  # DELETE /api/v1/mcp_servers/:id
  def destroy
    @mcp_server.destroy!

    render_success({
      message: "MCP server deleted successfully"
    })

    log_audit_event("mcp.servers.delete", @mcp_server)
  rescue StandardError => e
    Rails.logger.error "Failed to delete MCP server: #{e.message}"
    render_error("Failed to delete MCP server", status: :internal_server_error)
  end

  # POST /api/v1/mcp_servers/:id/connect
  def connect
    begin
      @mcp_server.connect!

      render_success({
        mcp_server: serialize_mcp_server(@mcp_server, include_tools: true),
        message: "MCP server connected successfully"
      })

      log_audit_event("mcp.servers.connect", @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to connect to MCP server: #{e.message}"
      @mcp_server.update(status: "error", last_error: e.message)
      render_error("Failed to connect: #{e.message}", status: :unprocessable_content)
    end
  end

  # POST /api/v1/mcp_servers/:id/disconnect
  def disconnect
    begin
      @mcp_server.disconnect!

      render_success({
        mcp_server: serialize_mcp_server(@mcp_server),
        message: "MCP server disconnected successfully"
      })

      log_audit_event("mcp.servers.disconnect", @mcp_server)
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

      log_audit_event("mcp.servers.health_check", @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Health check failed: #{e.message}"
      render_internal_error("Health check failed", exception: e)
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

      log_audit_event("mcp.servers.discover_tools", @mcp_server)
    rescue StandardError => e
      Rails.logger.error "Failed to discover tools: #{e.message}"
      render_error("Failed to discover tools: #{e.message}", status: :unprocessable_content)
    end
  end

  private

  def set_mcp_server
    @mcp_server = current_user.account.mcp_servers.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("MCP server not found", status: :not_found)
  end

  def require_read_permission
    unless current_user.has_permission?("mcp.servers.read")
      render_error("Insufficient permissions to view MCP servers", status: :forbidden)
    end
  end

  def require_write_permission
    unless current_user.has_permission?("mcp.servers.write")
      render_error("Insufficient permissions to manage MCP servers", status: :forbidden)
    end
  end

  # IMP-80e613fb9c43: config has no schema of its own (see
  # Api::V1::McpServerConfigSerialization), so reject anything outside the
  # allowlist at write time rather than silently dropping or storing it —
  # the serializer then never has hidden content to filter.
  #
  # review round 2 (BLOCKER): `mcp_server`/`config` can each arrive as a
  # scalar or array (a caller can send any JSON shape), and calling
  # `.to_unsafe_h` on anything but an ActionController::Parameters raises.
  # Every level is type-checked before being treated as an object; a
  # non-object at any level is itself a 422, never a 500.
  def validate_config_keys
    mcp_server_param = params[:mcp_server]
    unless mcp_server_param.is_a?(ActionController::Parameters)
      return render_error("mcp_server must be an object", status: :unprocessable_content)
    end

    config_param = mcp_server_param[:config]
    return if config_param.blank?

    unless config_param.is_a?(ActionController::Parameters)
      return render_error("config must be an object", status: :unprocessable_content)
    end

    violations = config_key_violations(config_param)
    return if violations.empty?

    render_error("Unsupported config key(s): #{violations.sort.join(', ')}", status: :unprocessable_content)
  end

  def config_key_violations(config_param)
    top_level = config_param.to_unsafe_h.keys.map(&:to_s) - ALLOWED_CONFIG_KEYS

    top_level +
      scalar_config_type_violations(config_param) +
      nested_config_violations(config_param, "capabilities", ALLOWED_CAPABILITIES_KEYS) { |v| v == true || v == false } +
      nested_config_violations(config_param, "metadata", ALLOWED_METADATA_KEYS) { |v| v.is_a?(String) }
  end

  # review round 4: a key-name allowlist alone does not stop a wrong-typed
  # VALUE on an otherwise-allowed key (`config: { version: {"api_key" =>
  # "..."} }` named an allowed key but held a smuggled hash). Driven by
  # the SAME CONFIG_KEY_TYPES map the serializer uses (see
  # Api::V1::McpServerConfigSerialization), so the two never drift. Only
  # the scalar (non-Hash) keys are checked here — capabilities/metadata's
  # shape and content are validated by nested_config_violations below,
  # which already covers "not a Hash at all" as well as their sub-keys.
  def scalar_config_type_violations(config_param)
    CONFIG_KEY_TYPES.filter_map do |key, type|
      next if type == Hash
      next unless config_param.key?(key)

      # Strict, no coercion: an integer-LOOKING string ("3") is rejected
      # for resources_count/prompts_count rather than accepted, so a
      # caller can't smuggle content through a type that happens to
      # stringify safely.
      key unless config_param[key].is_a?(type)
    end
  end

  # A nested key is a violation either because it isn't on the sub-allowlist
  # at all, or because its value doesn't match the type that key is allowed
  # to hold (see Api::V1::McpServerConfigSerialization's "second-level
  # allowlist" note — an allowed key name with a smuggled-in object/array
  # value is the same class of leak as a disallowed key).
  def nested_config_violations(config_param, key, allowed_keys)
    nested = config_param[key]
    return [] if nested.blank?
    return [ key ] unless nested.is_a?(ActionController::Parameters)

    nested.to_unsafe_h.filter_map do |k, v|
      "#{key}.#{k}" unless allowed_keys.include?(k.to_s) && yield(v)
    end
  end

  # IMP-2c760325c102 — `args` is an ARRAY of strings (McpServer validates
  # it as one); `permit(:args)` only ever admitted a scalar, so an array
  # sent by any client was silently dropped and every API-created stdio
  # server stored `args: []`. Surfaced by the save-time package-pinning
  # validation ("npx: no package was given to run") and fixed here, since
  # that validation has to see the same args the worker will spawn with.
  def mcp_server_params
    params.require(:mcp_server).permit(
      :name,
      :description,
      :connection_type,
      :command,
      :url,
      args: [],
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
      config: serialize_mcp_server_config(server),
      # IMP-2c760325c102 — see Api::V1::McpServerNativeExecutionActions.
      native_execution: serialize_native_execution(server),
      # IMP-cdda895b07a8 — see Api::V1::McpServerSecurityActions.
      security: serialize_security_capabilities(server),
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

end

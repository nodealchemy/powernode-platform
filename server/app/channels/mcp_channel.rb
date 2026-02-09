# frozen_string_literal: true

# MCP Channel - WebSocket channel for MCP protocol communication
# Replaces all legacy AI orchestration channels with unified MCP protocol
class McpChannel < ApplicationCable::Channel
  class ConnectionError < StandardError; end
  class AuthorizationError < StandardError; end
  class ProtocolError < StandardError; end

  def subscribed
    @logger = Rails.logger
    @logger.info "[MCP_CHANNEL] Connection attempt from user #{current_user&.id}"

    # Verify user authentication
    unless current_user
      @logger.warn "[MCP_CHANNEL] Unauthenticated connection attempt"
      reject_connection("Authentication required")
      return
    end

    # Verify MCP permissions
    unless has_mcp_permissions?
      @logger.warn "[MCP_CHANNEL] User #{current_user.id} lacks MCP permissions"
      reject_connection("Insufficient permissions for MCP access")
      return
    end

    # Initialize MCP connection
    initialize_mcp_connection

    # Subscribe to account-specific MCP streams
    setup_mcp_subscriptions

    # Send initialization response
    send_mcp_initialization_response

    @logger.info "[MCP_CHANNEL] User #{current_user.id} connected to MCP channel"
  end

  def unsubscribed
    @logger.info "[MCP_CHANNEL] User #{current_user&.id} disconnected from MCP channel"

    # Clean up MCP connection
    cleanup_mcp_connection
  end

  # =============================================================================
  # MCP PROTOCOL MESSAGE HANDLERS
  # =============================================================================

  # Handle MCP protocol initialization
  def initialize_protocol(data)
    @logger.info "[MCP_CHANNEL] Handling MCP protocol initialization"

    begin
      client_info = extract_client_info(data)
      response = @mcp_protocol.handle_initialize_request(client_info)

      transmit_mcp_message({
        id: data["id"],
        result: response
      })

    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle tool discovery requests
  def list_tools(data)
    @logger.debug "[MCP_CHANNEL] Handling tools list request"

    begin
      filters = data["params"] || {}
      result = @mcp_protocol.list_tools(filters)

      transmit_mcp_message({
        id: data["id"],
        result: result
      })

    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle tool description requests
  def describe_tool(data)
    @logger.debug "[MCP_CHANNEL] Handling tool description request"

    begin
      tool_id = data.dig("params", "name")
      raise ProtocolError, "Missing tool name" unless tool_id

      result = @mcp_protocol.describe_tool(tool_id)

      transmit_mcp_message({
        id: data["id"],
        result: result
      })

    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle tool invocation requests
  def call_tool(data)
    @logger.info "[MCP_CHANNEL] Handling tool call request"

    begin
      tool_name = data.dig("params", "name")
      arguments = data.dig("params", "arguments") || {}

      raise ProtocolError, "Missing tool name" unless tool_name

      # Add user context to execution options
      execution_options = {
        user: current_user,
        user_id: current_user.id,
        connection_id: @connection_id,
        channel: "mcp_channel"
      }

      result = @mcp_protocol.invoke_tool(tool_name, arguments, execution_options)

      transmit_mcp_message({
        id: data["id"],
        result: result
      })

    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle workflow execution requests
  def execute_workflow(data)
    @logger.info "[MCP_CHANNEL] Handling workflow execution request"

    begin
      workflow_id = data.dig("params", "workflow_id")
      input_variables = data.dig("params", "input_variables") || {}
      execution_options = data.dig("params", "execution_options") || {}

      raise ProtocolError, "Missing workflow_id" unless workflow_id

      # Find workflow
      workflow = current_user.account.ai_workflows.find(workflow_id)

      # Create workflow run
      workflow_run = workflow.create_run(
        input_variables: input_variables,
        triggered_by_user: current_user,
        trigger_type: "mcp_channel",
        trigger_context: {
          "connection_id" => @connection_id,
          "channel" => "mcp_channel"
        }
      )

      # Execute via MCP workflow service
      Mcp::AiWorkflowOrchestrator.new(
        workflow_run: workflow_run,
        account: current_user.account,
        user: current_user
      ).execute_workflow

      transmit_mcp_message({
        id: data["id"],
        result: {
          workflow_run_id: workflow_run.id,
          status: workflow_run.status,
          started_at: workflow_run.started_at.iso8601
        }
      })

    rescue ActiveRecord::RecordNotFound
      transmit_mcp_error(data["id"], ProtocolError.new("Workflow not found"))
    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle agent execution requests
  def execute_agent(data)
    @logger.info "[MCP_CHANNEL] Handling agent execution request"

    begin
      agent_id = data.dig("params", "agent_id")
      input_parameters = data.dig("params", "input_parameters") || {}
      execution_options = data.dig("params", "execution_options") || {}

      raise ProtocolError, "Missing agent_id" unless agent_id

      # Find agent
      agent = current_user.account.ai_agents.find(agent_id)

      # Execute via MCP
      result = agent.execute_via_mcp(input_parameters, execution_options.merge({
        user: current_user,
        connection_id: @connection_id
      }))

      transmit_mcp_message({
        id: data["id"],
        result: result
      })

    rescue ActiveRecord::RecordNotFound
      transmit_mcp_error(data["id"], ProtocolError.new("Agent not found"))
    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # Handle ping requests
  def ping(data)
    @logger.debug "[MCP_CHANNEL] Handling ping request"

    @mcp_transport.handle_ping(@connection_id)

    transmit_mcp_message({
      id: data["id"],
      result: {
        pong: true,
        timestamp: Time.current.iso8601,
        server_info: {
          name: "Powernode MCP Server",
          version: Rails.application.config.version || "1.0.0"
        }
      }
    })
  end

  # Handle resource subscription requests
  def subscribe_to_resource(data)
    @logger.info "[MCP_CHANNEL] Handling resource subscription"

    begin
      resource_type = data.dig("params", "resource_type")
      resource_id = data.dig("params", "resource_id")
      filters = data.dig("params", "filters") || {}

      case resource_type
      when "tool_events"
        subscribe_to_tool_events(resource_id, filters)
      when "workflow_events"
        subscribe_to_workflow_events(resource_id, filters)
      when "agent_events"
        subscribe_to_agent_events(resource_id, filters)
      else
        raise ProtocolError, "Unknown resource type: #{resource_type}"
      end

      transmit_mcp_message({
        id: data["id"],
        result: {
          subscribed: true,
          resource_type: resource_type,
          resource_id: resource_id
        }
      })

    rescue StandardError => e
      transmit_mcp_error(data["id"], e)
    end
  end

  # =============================================================================
  # MCP CONNECTION MANAGEMENT
  # =============================================================================

  private

  def initialize_mcp_connection
    @connection_id = SecureRandom.uuid

    # Initialize MCP services
    @mcp_protocol = Mcp::ProtocolService.new(
      account: current_user.account,
      connection_id: @connection_id
    )

    @mcp_transport = Mcp::TransportService.new(connection_id: @connection_id)
    @mcp_registry = Mcp::RegistryService.new(account: current_user.account)

    # Register connection
    @mcp_transport.register_connection(@connection_id, {
      user_id: current_user.id,
      account_id: current_user.account_id,
      connected_at: Time.current,
      user_agent: connection.try(:request)&.headers&.[]("User-Agent") || "Test Client",
      ip_address: connection.try(:request)&.remote_ip || "127.0.0.1"
    })

    # Register platform tools for MCP discovery
    Ai::Tools::McpPlatformToolRegistrar.register_all!(account: current_user.account)

    @logger.debug "[MCP_CHANNEL] MCP connection initialized: #{@connection_id}"
  end

  def setup_mcp_subscriptions
    account_id = current_user.account_id

    # Subscribe to account-wide MCP events
    stream_from "mcp_account_#{account_id}"

    # Subscribe to user-specific MCP events
    stream_from "mcp_user_#{current_user.id}"

    # Subscribe to tool registry changes
    stream_from "mcp_tools_#{account_id}"

    @logger.debug "[MCP_CHANNEL] MCP subscriptions configured for account #{account_id}"
  end

  def cleanup_mcp_connection
    return unless @connection_id

    @mcp_transport&.disconnect_connection(@connection_id)
    # Clean up the transport service instance to stop background threads
    @mcp_transport&.cleanup
    @logger.debug "[MCP_CHANNEL] MCP connection cleaned up: #{@connection_id}"
  end

  def has_mcp_permissions?
    # Check if user has any MCP-related permissions
    mcp_permissions = [
      "ai.agents.read",
      "ai.workflows.read",
      "ai.providers.read",
      "admin.access"
    ]

    mcp_permissions.any? { |permission| current_user.has_permission?(permission) }
  end

  def extract_client_info(data)
    params = data["params"] || {}

    {
      "protocolVersion" => params["protocolVersion"],
      "capabilities" => params["capabilities"] || {},
      "clientInfo" => params["clientInfo"] || {}
    }
  end

  # =============================================================================
  # MCP MESSAGE TRANSMISSION
  # =============================================================================

  def transmit_mcp_message(message)
    # Ensure message follows MCP JSON-RPC format
    mcp_message = {
      jsonrpc: "2.0"
    }.merge(message)

    # Add timestamp
    mcp_message[:timestamp] = Time.current.iso8601

    transmit(mcp_message)

    @logger.debug "[MCP_CHANNEL] Transmitted MCP message: #{mcp_message[:id] || 'notification'}"
  end

  def transmit_mcp_error(message_id, error)
    error_response = {
      id: message_id,
      error: {
        code: map_error_code(error),
        message: error.message,
        data: {
          type: error.class.name,
          timestamp: Time.current.iso8601
        }
      }
    }

    transmit_mcp_message(error_response)

    @logger.error "[MCP_CHANNEL] Transmitted MCP error: #{error.message}"
  end

  def send_mcp_initialization_response
    transmit_mcp_message({
      method: "initialized",
      params: {
        connection_id: @connection_id,
        server_capabilities: @mcp_protocol.build_server_capabilities,
        available_tools: @mcp_registry.list_tools.size,
        account_id: current_user.account_id,
        user_permissions: current_user.permission_names & mcp_related_permissions
      }
    })
  end

  # =============================================================================
  # RESOURCE SUBSCRIPTIONS
  # =============================================================================

  def subscribe_to_tool_events(tool_id, filters)
    if tool_id == "all"
      stream_from "mcp_tool_events_#{current_user.account_id}"
    else
      stream_from "mcp_tool_#{tool_id}_events"
    end
  end

  def subscribe_to_workflow_events(workflow_id, filters)
    if workflow_id == "all"
      stream_from "mcp_workflow_events_#{current_user.account_id}"
    else
      stream_from "mcp_workflow_#{workflow_id}_events"
    end
  end

  def subscribe_to_agent_events(agent_id, filters)
    if agent_id == "all"
      stream_from "mcp_agent_events_#{current_user.account_id}"
    else
      stream_from "mcp_agent_#{agent_id}_events"
    end
  end

  # =============================================================================
  # CLASS METHODS FOR BROADCASTING
  # =============================================================================

  def self.broadcast_to_account(account_id, message)
    broadcast_to("mcp_account_#{account_id}", {
      jsonrpc: "2.0",
      method: "notification",
      params: message.merge(timestamp: Time.current.iso8601)
    })
  end

  def self.broadcast_to_user(user_id, message)
    broadcast_to("mcp_user_#{user_id}", {
      jsonrpc: "2.0",
      method: "notification",
      params: message.merge(timestamp: Time.current.iso8601)
    })
  end

  def self.broadcast_tool_event(event_type, tool_id, data, account)
    message = {
      type: "tool_event",
      event_type: event_type,
      tool_id: tool_id,
      data: data
    }

    # Broadcast to account
    broadcast_to_account(account.id, message) if account

    # Broadcast to specific tool stream
    broadcast_to("mcp_tool_#{tool_id}_events", {
      jsonrpc: "2.0",
      method: "notification",
      params: message.merge(timestamp: Time.current.iso8601)
    })
  end

  def self.broadcast_workflow_event(event_type, workflow_id, data, account)
    message = {
      type: "workflow_event",
      event_type: event_type,
      workflow_id: workflow_id,
      data: data
    }

    broadcast_to_account(account.id, message) if account
  end

  def self.broadcast_to_connection(connection_id, message)
    # This would need to be implemented based on connection tracking
    # For now, we'll use the transport service
    transport = Mcp::TransportService.new(connection_id: connection_id)
    transport.send_message(connection_id, message)
  end

  # =============================================================================
  # UTILITY METHODS
  # =============================================================================

  def map_error_code(error)
    case error
    when AuthorizationError
      -32600  # Invalid request
    when ProtocolError
      -32602  # Invalid params
    when ActiveRecord::RecordNotFound
      -32601  # Method not found
    else
      -32603  # Internal error
    end
  end

  def mcp_related_permissions
    [
      "ai.agents.read", "ai.agents.create", "ai.agents.update", "ai.agents.delete",
      "ai.workflows.read", "ai.workflows.create", "ai.workflows.update", "ai.workflows.delete",
      "ai.providers.read", "ai.providers.update",
      "admin.access"
    ]
  end

  def reject_connection(reason)
    @logger.warn "[MCP_CHANNEL] Rejecting connection: #{reason}"
    reject
  end
end

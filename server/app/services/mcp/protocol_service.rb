# frozen_string_literal: true

# MCP Protocol Service - Core implementation of Model Context Protocol
# Handles all MCP JSON-RPC 2.0 message formatting, tool registration, and communication
module Mcp
  class ProtocolService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class ProtocolError < StandardError; end
  class ToolNotFoundError < ProtocolError; end
  class SchemaValidationError < ProtocolError; end
  class ConnectionError < ProtocolError; end
  class PermissionDeniedError < ProtocolError; end

  # MCP Protocol Version - Updated to 2025-06-18 specification
  MCP_VERSION = "2025-06-18"
  JSONRPC_VERSION = "2.0"

  # Supported protocol versions for negotiation (newest first)
  SUPPORTED_VERSIONS = [
    "2025-06-18",  # Current version with Streamable HTTP, OAuth 2.1
    "2024-11-05"   # Legacy version for backward compatibility
  ].freeze

  # Default version for clients that don't specify one (per spec)
  DEFAULT_VERSION = "2025-03-26"

  attr_accessor :account, :connection_id, :protocol_version

  def initialize(account: nil, connection_id: nil)
    @account = account
    @connection_id = connection_id || SecureRandom.uuid
    @protocol_version = MCP_VERSION
    @logger = Rails.logger
    @message_id_counter = 0
    @pending_requests = {}
    @tool_schemas = {}

    # Initialize core MCP components
    @registry = Mcp::RegistryService.new(account: @account)
    @transport = Mcp::TransportService.new(connection_id: @connection_id)
    @telemetry = Mcp::TelemetryService.new(account: @account)
  end

  # =============================================================================
  # MCP PROTOCOL HANDSHAKE AND INITIALIZATION
  # =============================================================================

  # Initialize MCP connection with capability negotiation
  def initialize_connection(client_info = {})
    @logger.info "[MCP] Initializing connection #{@connection_id}"

    # Build server capabilities manifest
    server_capabilities = build_server_capabilities

    # Create initialization response
    init_response = create_mcp_message(
      method: "initialize",
      params: {
        protocolVersion: @protocol_version,
        capabilities: server_capabilities,
        serverInfo: {
          name: "Powernode AI Platform",
          version: Rails.application.config.version || "1.0.0"
        }
      }
    )

    # Register connection in transport layer
    @transport.register_connection(@connection_id, client_info)

    # Track telemetry
    @telemetry.track_connection_init(@connection_id, client_info)

    init_response
  end

  # Handle ping requests
  def handle_ping
    {
      "pong" => true,
      "timestamp" => Time.current.iso8601,
      "server_info" => {
        "name" => "Powernode MCP Server",
        "version" => Rails.application.config.version || "1.0.0"
      }
    }
  end

  # Handle protocol initialization request
  def handle_initialize_request(client_info)
    @logger.info "[MCP] Handling initialize request from #{client_info['clientInfo']&.dig('name')}"

    # Validate protocol version compatibility
    client_version = client_info["protocolVersion"]
    unless protocol_version_compatible?(client_version)
      raise ProtocolError, "Unsupported protocol version: #{client_version}"
    end

    # Build response
    {
      "connection_id" => @connection_id,
      "server_capabilities" => build_server_capabilities,
      "available_tools" => @registry.list_tools.size,
      "user_permissions" => extract_user_permissions
    }
  end


  # =============================================================================
  # TOOL DISCOVERY AND REGISTRATION
  # =============================================================================

  # Register a tool with the MCP registry
  def register_tool(tool_manifest)
    validate_tool_manifest!(tool_manifest)

    tool_id = generate_tool_id(tool_manifest)
    @registry.register_tool(tool_id, tool_manifest)
    @tool_schemas[tool_id] = tool_manifest["inputSchema"]

    @logger.info "[MCP] Registered tool: #{tool_id}"
    @telemetry.track_tool_registration(tool_id, tool_manifest)

    tool_id
  end

  # List all available tools for client discovery (with permission filtering)
  def list_tools(filters = {}, user: nil)
    tools = @registry.list_tools(filters)

    # Filter tools based on user permissions and account scope
    if user && @account
      tools = tools.select do |tool_manifest|
        # Get the database record for permission checking
        mcp_tool = McpTool.find_by(name: tool_manifest["name"])
        next true unless mcp_tool # Include if no database record (legacy tools)

        # Check if user can access this tool
        validator = McpPermissionValidator.new(
          tool: mcp_tool,
          user: user,
          account: @account
        )
        validator.authorized?
      end
    end

    {
      "tools" => tools.map { |tool| format_tool_for_discovery(tool) }
    }
  end

  # Get detailed information about a specific tool
  def describe_tool(tool_id)
    tool_manifest = @registry.get_tool(tool_id)
    raise ToolNotFoundError, "Tool not found: #{tool_id}" unless tool_manifest

    {
      "name" => tool_manifest["name"],
      "description" => tool_manifest["description"],
      "type" => tool_manifest["type"] || "ai_agent",
      "inputSchema" => tool_manifest["inputSchema"],
      "outputSchema" => tool_manifest["outputSchema"],
      "capabilities" => tool_manifest["capabilities"] || [],
      "version" => tool_manifest["version"] || "1.0.0"
    }
  end

  # =============================================================================
  # TOOL INVOCATION AND EXECUTION
  # =============================================================================

  # Invoke a tool with MCP protocol
  def invoke_tool(tool_id, params = {}, options = {})
    @logger.info "[MCP] Invoking tool: #{tool_id}"

    # Get tool manifest
    tool_manifest = @registry.get_tool(tool_id)
    raise ToolNotFoundError, "Tool not found: #{tool_id}" unless tool_manifest

    # Get the actual McpTool database record for permission checking
    mcp_tool = McpTool.find_by(name: tool_manifest["name"])
    user = options[:user]

    # Validate permissions before execution
    if mcp_tool && user
      validator = McpPermissionValidator.new(
        tool: mcp_tool,
        user: user,
        account: @account
      )

      unless validator.authorized?
        auth_result = validator.authorization_result
        error_messages = auth_result[:errors].map { |e| e[:message] }.join("; ")

        @logger.warn "[MCP] Permission denied for tool #{tool_id}: #{error_messages}"
        @telemetry.track_tool_permission_denied(tool_id, user, auth_result)

        raise PermissionDeniedError, "Permission denied: #{error_messages}"
      end

      @logger.info "[MCP] Permission check passed for tool #{tool_id}"
    else
      @logger.warn "[MCP] Skipping permission check - tool or user not found"
    end

    # Validate input parameters
    validate_tool_input!(tool_id, params)

    # Create execution context
    execution_context = build_execution_context(tool_id, params, options)

    # Track invocation start
    execution_id = SecureRandom.uuid
    @telemetry.track_tool_invocation_start(execution_id, tool_id, params)

    begin
      # Route to appropriate executor based on tool type
      result = execute_tool_by_type(tool_manifest, params, execution_context)

      # Validate output against schema
      validate_tool_output!(tool_id, result)

      # Track successful completion
      @telemetry.track_tool_invocation_complete(execution_id, result)

      # Format MCP response
      create_mcp_response(result: result, id: execution_id)

    rescue StandardError => e
      @telemetry.track_tool_invocation_error(execution_id, e)
      raise
    end
  end

  # =============================================================================
  # MCP MESSAGE HANDLING
  # =============================================================================

  # Process incoming MCP message
  def process_message(message_data)
    @logger.debug "[MCP] Processing message: #{message_data.class}"

    # Parse and validate MCP message format
    message = parse_mcp_message(message_data)
    validate_mcp_message!(message)

    # Route based on message type
    case message["method"]
    when "initialize"
      handle_initialize_request(message["params"] || {})
    when "tools/list"
      list_tools(message["params"] || {})
    when "tools/call"
      tool_id = message.dig("params", "name")
      arguments = message.dig("params", "arguments") || {}
      invoke_tool(tool_id, arguments)
    when "tools/describe"
      tool_id = message.dig("params", "name")
      describe_tool(tool_id)
    when "ping"
      { pong: true, timestamp: Time.current.iso8601 }
    else
      raise ProtocolError, "Unknown method: #{message['method']}"
    end
  end

  # Create standardized MCP message
  def create_mcp_message(method:, params: nil, id: nil)
    message = {
      jsonrpc: JSONRPC_VERSION,
      method: method
    }

    message[:id] = id || generate_message_id
    message[:params] = params if params

    message
  end

  # Create MCP response message
  def create_mcp_response(result: nil, error: nil, id: nil)
    response = {
      jsonrpc: JSONRPC_VERSION,
      id: id || generate_message_id
    }

    if error
      response[:error] = format_mcp_error(error)
    else
      response[:result] = result
    end

    response
  end

  # Build server capabilities for MCP protocol
  def build_server_capabilities
    {
      "protocolVersion" => @protocol_version,
      "tools" => {
        "listChanged" => true
      },
      "resources" => {
        "subscribe" => true,
        "listChanged" => true
      },
      "prompts" => {
        "listChanged" => false
      }
    }
  end

  # =============================================================================
  # PRIVATE HELPER METHODS
  # =============================================================================

  private


  def protocol_compatible?(client_version)
    # Accept any supported version
    return true if SUPPORTED_VERSIONS.include?(client_version)

    # Per MCP spec: if client doesn't specify, use default version
    return true if client_version.nil? || client_version.empty?

    false
  end

  # Negotiate the best protocol version between client and server
  # Returns the negotiated version or nil if incompatible
  def self.negotiate_protocol_version(client_version)
    # If client doesn't specify, use default per spec
    return DEFAULT_VERSION if client_version.nil? || client_version.empty?

    # Return the client version if we support it
    return client_version if SUPPORTED_VERSIONS.include?(client_version)

    # Otherwise, return nil to indicate incompatibility
    nil
  end

  # Validate that the message is not a JSON-RPC batch request
  # MCP 2025-06-18 removed batching support
  def self.validate_not_batch(data)
    parsed = data.is_a?(String) ? JSON.parse(data) : data
    if parsed.is_a?(Array)
      raise ProtocolError, "JSON-RPC batching is not supported in MCP 2025-06-18"
    end
    parsed
  rescue JSON::ParserError => e
    raise ProtocolError, "Invalid JSON: #{e.message}"
  end

  def validate_tool_manifest!(manifest)
    required_fields = %w[name description inputSchema outputSchema]
    missing_fields = required_fields - manifest.keys

    if missing_fields.any?
      raise SchemaValidationError, "Missing required fields: #{missing_fields.join(', ')}"
    end

    # Validate JSON schema format
    validate_json_schema!(manifest["inputSchema"])
    validate_json_schema!(manifest["outputSchema"])
  end

  def generate_tool_id(manifest)
    # Create deterministic tool ID from manifest
    name = manifest["name"]
    version = manifest["version"] || "1.0.0"
    "#{name.downcase.gsub(/[^a-z0-9]/, '_')}_v#{version.gsub('.', '_')}"
  end

  def format_tool_for_discovery(tool)
    {
      "name" => tool["name"],
      "description" => tool["description"],
      "type" => tool["type"] || "ai_agent",
      "version" => tool["version"] || "1.0.0",
      "capabilities" => tool["capabilities"] || []
    }
  end

  def validate_tool_input!(tool_id, params)
    schema = @tool_schemas[tool_id]
    return unless schema

    # Use JSON Schema validation
    validator = JsonSchemaValidator.new(schema)
    unless validator.valid?(params)
      raise SchemaValidationError, "Invalid input: #{validator.errors.join(', ')}"
    end
  end

  def validate_tool_output!(tool_id, result)
    tool_manifest = @registry.get_tool(tool_id)
    schema = tool_manifest["outputSchema"]
    return unless schema

    validator = JsonSchemaValidator.new(schema)
    unless validator.valid?(result)
      @logger.warn "[MCP] Tool output validation failed for #{tool_id}: #{validator.errors}"
    end
  end

  def build_execution_context(tool_id, params, options)
    {
      tool_id: tool_id,
      connection_id: @connection_id,
      account_id: @account&.id,
      user_id: options[:user_id],
      execution_id: SecureRandom.uuid,
      started_at: Time.current,
      options: options
    }
  end

  def execute_tool_by_type(tool_manifest, params, context)
    tool_type = tool_manifest["type"] || "ai_agent"

    case tool_type
    when "ai_agent"
      agent_id = tool_manifest["metadata"]["agent_id"]
      agent = @account.ai_agents.find(agent_id)
      executor = Ai::McpAgentExecutor.new(agent: agent, account: @account)
      executor.execute(params)
    when "workflow"
      workflow_id = tool_manifest["metadata"]["workflow_id"]
      workflow = @account.ai_workflows.find(workflow_id)
      executor = McpWorkflowExecutor.new(workflow: workflow, account: @account)
      executor.execute(params)
    else
      raise ProtocolError, "Unknown tool type: #{tool_type}"
    end
  end

  def parse_mcp_message(data)
    case data
    when String
      JSON.parse(data)
    when Hash
      data
    else
      raise ProtocolError, "Invalid message format"
    end
  rescue JSON::ParserError => e
    raise ProtocolError, "Invalid JSON: #{e.message}"
  end

  def validate_mcp_message!(message)
    unless message["jsonrpc"] == JSONRPC_VERSION
      raise ProtocolError, "Invalid JSON-RPC version: #{message['jsonrpc']}"
    end

    unless message["method"].present?
      raise ProtocolError, "Missing method field"
    end
  end

  def validate_json_schema!(schema)
    # Basic JSON Schema validation
    return if schema.blank?

    unless schema.is_a?(Hash) && schema["type"].present?
      raise SchemaValidationError, "Invalid JSON schema format"
    end
  end

  def generate_message_id
    @message_id_counter += 1
    "#{@connection_id}_#{@message_id_counter}"
  end

  def format_mcp_error(error)
    {
      code: error_code_for_exception(error),
      message: error.message,
      data: {
        type: error.class.name,
        timestamp: Time.current.iso8601
      }
    }
  end

  def error_code_for_exception(error)
    case error
    when PermissionDeniedError
      -32001  # Permission denied (custom error code)
    when ToolNotFoundError
      -32601  # Method not found
    when SchemaValidationError
      -32602  # Invalid params
    when ConnectionError
      -32603  # Internal error
    else
      -32603  # Internal error
    end
  end

  # Helper methods for protocol compatibility
  def protocol_version_compatible?(client_version)
    return true if client_version.nil? || client_version == @protocol_version

    # Allow compatible versions (same major version)
    client_major = client_version.split("-").first
    server_major = @protocol_version.split("-").first
    client_major == server_major
  end

  def extract_user_permissions
    return [] unless @account

    # Return account-level permissions for MCP operations
    [
      "ai.agents.read",
      "ai.workflows.read",
      "ai.providers.read"
    ]
  end


  def create_error_response(message_id, error_message, error_code)
    {
      "jsonrpc" => JSONRPC_VERSION,
      "id" => message_id,
      "error" => {
        "code" => error_code,
        "message" => error_message,
        "data" => {
          "timestamp" => Time.current.iso8601
        }
      }
    }
  end
  end
end

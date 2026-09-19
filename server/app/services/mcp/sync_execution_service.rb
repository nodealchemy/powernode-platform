# frozen_string_literal: true

# Service for synchronous MCP tool execution
# Handles in-process execution for stdio, http, and websocket connection types
module Mcp
  class SyncExecutionService
  def initialize(server:, tool:, parameters:, user:, account:)
    @server = server
    @tool = tool
    @parameters = parameters
    @user = user
    @account = account
    @logger = Rails.logger
  end

  def execute
    start_time = Time.current

    begin
      result = case @server.connection_type
      when "stdio"
                 execute_stdio
      when "http"
                 execute_http
      when "websocket"
                 execute_websocket
      else
                 { success: false, error: "Unknown connection type: #{@server.connection_type}" }
      end

      execution_time_ms = ((Time.current - start_time) * 1000).round
      result.merge(execution_time_ms: execution_time_ms)
    rescue StandardError => e
      @logger.error "[McpSyncExecutionService] Execution failed: #{e.message}"
      @logger.error e.backtrace.first(10).join("\n")
      { success: false, error: e.message, execution_time_ms: ((Time.current - start_time) * 1000).round }
    end
  end

  private

  # IMP-176a386fef98: this used to validate only the bare command STRING
  # (never args), sanitize env with plain string-key filtering (no
  # unsetenv_others), and spawn @server.command as a bare STRING with
  # `*Array(@server.args)` — Process.spawn/Open3 runs a lone command
  # STRING through `/bin/sh -c` when given no additional args, so an empty
  # `args` would have let the command string alone execute arbitrary
  # shell syntax. It also inherited this RAILS PROCESS's full environment
  # (DATABASE_URL, secret_key_base, ...) since `unsetenv_others` was never
  # set. Routed through Mcp::SecurityService.validate_stdio_server! for
  # early, no-network-hop refusal of an obviously bad config (unchanged
  # since then). The returned error SHAPE is unchanged (`{success: false,
  # error: "Security error: ..."}`), never raised out of this service.
  #
  # IMP-abda86fb39be (MCP isolation Phase 0 T1): actual EXECUTION no
  # longer happens here. Once validated, the request goes to
  # Mcp::WorkerStdioClient, which POSTs it to the worker's own hardened
  # spawn_stdio (see that file's comment for the full data flow and the
  # tenancy/error-mapping reasoning). The response is a symbolized
  # `{result:}`/`{error:{message:}}` Hash — mapped through the SAME
  # `if response[:error] ... else {success:true, output: response[:result]}`
  # branch this method already used for its local `#parse_mcp_response`
  # result (that now-unused private method is removed below — nothing
  # else in this file called it). A worker-side timeout now arrives as
  # `{error:{message: "...exceeded Ns..."}}` here (handled by that same
  # branch) rather than a raised Mcp::SecurityService::StdioTimeoutError
  # caught by #execute's outer rescue — same final
  # `{success:false, error: <same text>, execution_time_ms: ...}` result
  # (#execute still appends execution_time_ms), one branch earlier. A
  # worker-unreachable/5xx failure is a genuinely NEW failure mode
  # (execution used to be in-process) and is NOT translated here:
  # WorkerTransport::HttpError/TimeoutError/ConnectionError (all
  # StandardError) propagate to #execute's existing outer
  # `rescue StandardError` unchanged.
  def execute_stdio
    server_hash = {
      "command" => @server.command,
      "args" => @server.args,
      "env" => @server.env,
      "capabilities" => @server.capabilities
    }

    begin
      Mcp::SecurityService.validate_stdio_server!(server_hash)
    rescue Mcp::SecurityService::CommandNotAllowedError => e
      @logger.error "[McpSyncExecutionService] Security violation - command blocked: #{e.message}"
      return { success: false, error: "Security error: #{e.message}" }
    rescue Mcp::SecurityService::EnvironmentViolationError => e
      @logger.error "[McpSyncExecutionService] Security violation - environment blocked: #{e.message}"
      return { success: false, error: "Security error: #{e.message}" }
    end

    mcp_request = build_mcp_request

    @logger.debug "[McpSyncExecutionService] Executing stdio command: #{@server.command}"

    response = Mcp::WorkerStdioClient.execute(account_id: @account.id, server: server_hash, mcp_request: mcp_request)

    if response[:error]
      { success: false, error: response[:error][:message] || response[:error]["message"] }
    else
      { success: true, output: response[:result] || response["result"] }
    end
  end

  def execute_http
    # Use Streamable HTTP transport if server supports MCP 2025-06-18
    if supports_streamable_http?
      execute_streamable_http
    else
      execute_legacy_http
    end
  end

  # Modern Streamable HTTP transport (MCP 2025-06-18)
  def execute_streamable_http
    @logger.debug "[McpSyncExecutionService] Using Streamable HTTP transport"

    service = Mcp::StreamableHttpService.new(
      server: @server,
      user: @user,
      account: @account
    )

    result = service.call_tool(name: @tool.name, arguments: @parameters)

    if result[:success]
      { success: true, output: result[:result] }
    elsif result[:retry] && !@streamable_retry
      # Token was refreshed, retry once
      @streamable_retry = true
      execute_streamable_http
    else
      { success: false, error: result[:error] }
    end
  rescue Mcp::StreamableHttpService::StreamableHttpError => e
    @logger.error "[McpSyncExecutionService] Streamable HTTP error: #{e.message}"
    { success: false, error: e.message }
  end

  # Legacy HTTP transport for older servers
  def execute_legacy_http
    require "net/http"

    url = @server.capabilities&.dig("url") || @server.env&.dig("url")
    raise "No URL configured for HTTP MCP server" unless url

    uri = URI("#{url}/tools/call")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 60
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["MCP-Protocol-Version"] = Mcp::ProtocolService::MCP_VERSION

    # Inject OAuth token or other authorization
    inject_authorization_header(request)

    mcp_request = build_mcp_request
    request.body = mcp_request.to_json

    @logger.debug "[McpSyncExecutionService] Executing legacy HTTP request to: #{uri}"

    response = http.request(request)

    case response.code.to_i
    when 200..299
      result = JSON.parse(response.body)
      if result["error"]
        { success: false, error: result["error"]["message"] || result["error"].to_s }
      else
        { success: true, output: result["result"] }
      end
    when 401
      # Token may have expired, try refreshing once
      if @server.auth_type == "oauth2" && !@retry_auth
        @retry_auth = true
        refresh_and_retry_http(request, http)
      else
        { success: false, error: "HTTP error 401: Unauthorized - #{response.body.truncate(500)}" }
      end
    else
      { success: false, error: "HTTP error #{response.code}: #{response.body.truncate(500)}" }
    end
  end

  # Check if server supports Streamable HTTP transport
  def supports_streamable_http?
    # Server capabilities may indicate transport support
    transport = @server.capabilities&.dig("transport") || @server.env&.dig("transport")
    protocol_version = @server.capabilities&.dig("protocolVersion")

    # Use streamable if explicitly set or protocol version is 2025-06-18+
    transport == "streamable_http" ||
      protocol_version == "2025-06-18" ||
      @server.env&.dig("streamable_http")&.to_s == "true"
  end

  def execute_websocket
    # WebSocket execution requires persistent connection
    # For sync execution, we'll attempt a quick connect/call/disconnect cycle
    @logger.warn "[McpSyncExecutionService] WebSocket sync execution - using HTTP fallback or connection pool"

    # Try to use existing WebSocket connection if available
    if @server.capabilities&.dig("http_fallback_url")
      original_url = @server.capabilities["url"]
      @server.capabilities["url"] = @server.capabilities["http_fallback_url"]
      result = execute_http
      @server.capabilities["url"] = original_url
      result
    else
      { success: false, error: "WebSocket sync execution not supported without http_fallback_url" }
    end
  end

  def build_mcp_request
    {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      method: "tools/call",
      params: {
        name: @tool.name,
        arguments: @parameters
      }
    }
  end

  # Inject the appropriate authorization header based on auth_type
  def inject_authorization_header(request)
    case @server.auth_type
    when "oauth2"
      inject_oauth_token(request)
    when "api_key"
      inject_api_key(request)
    else
      # Fall back to env authorization if present
      if @server.env&.dig("authorization")
        request["Authorization"] = @server.env["authorization"]
      end
    end
  end

  # Inject OAuth 2.1 Bearer token
  def inject_oauth_token(request)
    oauth_service = Mcp::OauthService.new(@server)

    begin
      access_token = oauth_service.get_valid_access_token

      if access_token.present?
        token_type = @server.oauth_token_type || "Bearer"
        request["Authorization"] = "#{token_type} #{access_token}"
        @logger.debug "[McpSyncExecutionService] Injected OAuth token for server #{@server.name}"
      else
        @logger.warn "[McpSyncExecutionService] No OAuth token available for server #{@server.name}"
      end
    rescue Mcp::OauthService::TokenRefreshError => e
      @logger.error "[McpSyncExecutionService] OAuth token refresh failed: #{e.message}"
      # Continue without token - let the request fail with 401
    end
  end

  # Inject API key for servers using api_key authentication
  def inject_api_key(request)
    api_key = @server.env&.dig("api_key") || @server.env&.dig("API_KEY")
    return unless api_key.present?

    # Check for custom header name, default to Authorization with Bearer
    header_name = @server.env&.dig("api_key_header") || "Authorization"
    header_prefix = @server.env&.dig("api_key_prefix") || "Bearer"

    if header_name.casecmp("authorization").zero?
      request["Authorization"] = "#{header_prefix} #{api_key}"
    else
      request[header_name] = api_key
    end
  end

  # Attempt to refresh OAuth token and retry the HTTP request
  def refresh_and_retry_http(request, http)
    @logger.info "[McpSyncExecutionService] Attempting OAuth token refresh for server #{@server.name}"

    oauth_service = Mcp::OauthService.new(@server)

    begin
      oauth_service.refresh_token!
      @server.reload

      # Re-inject the new token
      inject_oauth_token(request)

      # Retry the request
      response = http.request(request)

      case response.code.to_i
      when 200..299
        result = JSON.parse(response.body)
        if result["error"]
          { success: false, error: result["error"]["message"] || result["error"].to_s }
        else
          { success: true, output: result["result"] }
        end
      else
        { success: false, error: "HTTP error #{response.code} after token refresh: #{response.body.truncate(500)}" }
      end
    rescue Mcp::OauthService::TokenRefreshError => e
      @logger.error "[McpSyncExecutionService] Token refresh failed: #{e.message}"
      { success: false, error: "OAuth token refresh failed: #{e.message}" }
    end
  end
  end
end

# frozen_string_literal: true

# Service for synchronous MCP tool execution
# Handles in-process execution for stdio, http, and websocket connection types
class McpSyncExecutionService
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
               when 'stdio'
                 execute_stdio
               when 'http'
                 execute_http
               when 'websocket'
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

  def execute_stdio
    require 'open3'

    # Security validation - command whitelist and environment sanitization
    begin
      validated = McpSecurityService.validate_stdio_execution!(
        command: @server.command,
        env: @server.env,
        allow_extended: @server.capabilities&.dig('allow_extended_commands') == true,
        strict_env: @server.capabilities&.dig('strict_environment') == true
      )
    rescue McpSecurityService::CommandNotAllowedError => e
      @logger.error "[McpSyncExecutionService] Security violation - command blocked: #{e.message}"
      return { success: false, error: "Security error: #{e.message}" }
    rescue McpSecurityService::EnvironmentViolationError => e
      @logger.error "[McpSyncExecutionService] Security violation - environment blocked: #{e.message}"
      return { success: false, error: "Security error: #{e.message}" }
    end

    mcp_request = build_mcp_request
    stdin_data = "#{mcp_request.to_json}\n"

    @logger.debug "[McpSyncExecutionService] Executing stdio command: #{@server.command}"

    # Build environment with sanitized values
    env = validated[:env].transform_keys(&:to_s)

    # Execute the command
    stdout, stderr, status = Open3.capture3(
      env,
      @server.command,
      *Array(@server.args),
      stdin_data: stdin_data
    )

    if status.success?
      response = parse_mcp_response(stdout)
      if response[:error]
        { success: false, error: response[:error][:message] || response[:error]['message'] }
      else
        { success: true, output: response[:result] || response['result'] }
      end
    else
      @logger.error "[McpSyncExecutionService] Process failed: #{stderr}"
      { success: false, error: "Process exited with code #{status.exitstatus}: #{stderr.truncate(500)}" }
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

    service = McpStreamableHttpService.new(
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
  rescue McpStreamableHttpService::StreamableHttpError => e
    @logger.error "[McpSyncExecutionService] Streamable HTTP error: #{e.message}"
    { success: false, error: e.message }
  end

  # Legacy HTTP transport for older servers
  def execute_legacy_http
    require 'net/http'

    url = @server.capabilities&.dig('url') || @server.env&.dig('url')
    raise "No URL configured for HTTP MCP server" unless url

    uri = URI("#{url}/tools/call")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 60
    http.open_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
    request['MCP-Protocol-Version'] = McpProtocolService::MCP_VERSION

    # Inject OAuth token or other authorization
    inject_authorization_header(request)

    mcp_request = build_mcp_request
    request.body = mcp_request.to_json

    @logger.debug "[McpSyncExecutionService] Executing legacy HTTP request to: #{uri}"

    response = http.request(request)

    case response.code.to_i
    when 200..299
      result = JSON.parse(response.body)
      if result['error']
        { success: false, error: result['error']['message'] || result['error'].to_s }
      else
        { success: true, output: result['result'] }
      end
    when 401
      # Token may have expired, try refreshing once
      if @server.auth_type == 'oauth2' && !@retry_auth
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
    transport = @server.capabilities&.dig('transport') || @server.env&.dig('transport')
    protocol_version = @server.capabilities&.dig('protocolVersion')

    # Use streamable if explicitly set or protocol version is 2025-06-18+
    transport == 'streamable_http' ||
      protocol_version == '2025-06-18' ||
      @server.env&.dig('streamable_http')&.to_s == 'true'
  end

  def execute_websocket
    # WebSocket execution requires persistent connection
    # For sync execution, we'll attempt a quick connect/call/disconnect cycle
    @logger.warn "[McpSyncExecutionService] WebSocket sync execution - using HTTP fallback or connection pool"

    # Try to use existing WebSocket connection if available
    if @server.capabilities&.dig('http_fallback_url')
      original_url = @server.capabilities['url']
      @server.capabilities['url'] = @server.capabilities['http_fallback_url']
      result = execute_http
      @server.capabilities['url'] = original_url
      result
    else
      { success: false, error: "WebSocket sync execution not supported without http_fallback_url" }
    end
  end

  def build_mcp_request
    {
      jsonrpc: '2.0',
      id: SecureRandom.uuid,
      method: 'tools/call',
      params: {
        name: @tool.name,
        arguments: @parameters
      }
    }
  end

  def parse_mcp_response(json_string)
    # MCP responses may contain multiple JSON objects (ndjson)
    # We want the last valid response that contains a result or error
    lines = json_string.strip.split("\n")

    lines.reverse_each do |line|
      next if line.strip.empty?

      begin
        parsed = JSON.parse(line)
        # Check if this is a valid MCP response
        if parsed.key?('result') || parsed.key?('error')
          return parsed.deep_symbolize_keys
        end
      rescue JSON::ParserError
        next
      end
    end

    { error: { message: 'No valid MCP response received' } }
  end

  # Inject the appropriate authorization header based on auth_type
  def inject_authorization_header(request)
    case @server.auth_type
    when 'oauth2'
      inject_oauth_token(request)
    when 'api_key'
      inject_api_key(request)
    else
      # Fall back to env authorization if present
      if @server.env&.dig('authorization')
        request['Authorization'] = @server.env['authorization']
      end
    end
  end

  # Inject OAuth 2.1 Bearer token
  def inject_oauth_token(request)
    oauth_service = McpOauthService.new(@server)

    begin
      access_token = oauth_service.get_valid_access_token

      if access_token.present?
        token_type = @server.oauth_token_type || 'Bearer'
        request['Authorization'] = "#{token_type} #{access_token}"
        @logger.debug "[McpSyncExecutionService] Injected OAuth token for server #{@server.name}"
      else
        @logger.warn "[McpSyncExecutionService] No OAuth token available for server #{@server.name}"
      end
    rescue McpOauthService::TokenRefreshError => e
      @logger.error "[McpSyncExecutionService] OAuth token refresh failed: #{e.message}"
      # Continue without token - let the request fail with 401
    end
  end

  # Inject API key for servers using api_key authentication
  def inject_api_key(request)
    api_key = @server.env&.dig('api_key') || @server.env&.dig('API_KEY')
    return unless api_key.present?

    # Check for custom header name, default to Authorization with Bearer
    header_name = @server.env&.dig('api_key_header') || 'Authorization'
    header_prefix = @server.env&.dig('api_key_prefix') || 'Bearer'

    if header_name.casecmp('authorization').zero?
      request['Authorization'] = "#{header_prefix} #{api_key}"
    else
      request[header_name] = api_key
    end
  end

  # Attempt to refresh OAuth token and retry the HTTP request
  def refresh_and_retry_http(request, http)
    @logger.info "[McpSyncExecutionService] Attempting OAuth token refresh for server #{@server.name}"

    oauth_service = McpOauthService.new(@server)

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
        if result['error']
          { success: false, error: result['error']['message'] || result['error'].to_s }
        else
          { success: true, output: result['result'] }
        end
      else
        { success: false, error: "HTTP error #{response.code} after token refresh: #{response.body.truncate(500)}" }
      end
    rescue McpOauthService::TokenRefreshError => e
      @logger.error "[McpSyncExecutionService] Token refresh failed: #{e.message}"
      { success: false, error: "OAuth token refresh failed: #{e.message}" }
    end
  end
end

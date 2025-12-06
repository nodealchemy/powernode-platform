# frozen_string_literal: true

# Service for MCP Streamable HTTP transport (2025-06-18 spec)
# Implements the modern HTTP transport with:
# - Single endpoint for all requests (POST) and SSE streams (GET)
# - Content negotiation via Accept headers
# - Protocol version headers
# - Server-Sent Events (SSE) response handling
class McpStreamableHttpService
  MCP_PROTOCOL_VERSION = "2025-06-18"

  class StreamableHttpError < StandardError; end
  class ConnectionError < StreamableHttpError; end
  class ProtocolError < StreamableHttpError; end
  class TimeoutError < StreamableHttpError; end

  def initialize(server:, user: nil, account: nil)
    @server = server
    @user = user
    @account = account
    @logger = Rails.logger
    @session_id = nil
  end

  # Initialize the MCP protocol over Streamable HTTP
  def initialize_protocol
    response = send_request(
      method: "initialize",
      params: {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: client_capabilities,
        clientInfo: {
          name: "Powernode Server",
          version: "1.0.0"
        }
      }
    )

    if response[:success]
      # Send initialized notification
      send_notification(method: "notifications/initialized")

      # Extract session ID if provided in response headers
      @session_id = response[:headers]&.dig("mcp-session-id")
    end

    response
  end

  # List available tools from the server
  def list_tools(cursor: nil)
    params = {}
    params[:cursor] = cursor if cursor.present?

    send_request(method: "tools/list", params: params)
  end

  # Call a specific tool
  def call_tool(name:, arguments: {})
    send_request(
      method: "tools/call",
      params: {
        name: name,
        arguments: arguments
      }
    )
  end

  # List available resources
  def list_resources(cursor: nil)
    params = {}
    params[:cursor] = cursor if cursor.present?

    send_request(method: "resources/list", params: params)
  end

  # Read a specific resource
  def read_resource(uri:)
    send_request(
      method: "resources/read",
      params: { uri: uri }
    )
  end

  # List available prompts
  def list_prompts(cursor: nil)
    params = {}
    params[:cursor] = cursor if cursor.present?

    send_request(method: "prompts/list", params: params)
  end

  # Get a specific prompt
  def get_prompt(name:, arguments: {})
    send_request(
      method: "prompts/get",
      params: {
        name: name,
        arguments: arguments
      }
    )
  end

  # Open an SSE stream for server-to-client notifications
  # Yields events as they arrive
  def open_sse_stream(&block)
    return unless block_given?

    uri = build_uri
    http = build_http_client(uri)

    request = Net::HTTP::Get.new(uri)
    apply_common_headers(request)
    request["Accept"] = "text/event-stream"
    request["Cache-Control"] = "no-cache"

    @logger.info "[McpStreamableHttpService] Opening SSE stream to #{uri}"

    begin
      http.request(request) do |response|
        handle_sse_response(response, &block)
      end
    rescue StandardError => e
      @logger.error "[McpStreamableHttpService] SSE stream error: #{e.message}"
      raise ConnectionError, "SSE stream failed: #{e.message}"
    end
  end

  # Ping the server
  def ping
    send_request(method: "ping")
  end

  private

  # Send a JSON-RPC request via POST
  def send_request(method:, params: nil)
    uri = build_uri
    http = build_http_client(uri)

    request = build_post_request(uri, method, params)

    @logger.debug "[McpStreamableHttpService] Sending request: #{method}"

    begin
      response = http.request(request)
      parse_response(response)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      @logger.error "[McpStreamableHttpService] Timeout: #{e.message}"
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue StandardError => e
      @logger.error "[McpStreamableHttpService] Request failed: #{e.message}"
      raise ConnectionError, "Request failed: #{e.message}"
    end
  end

  # Send a JSON-RPC notification (no response expected)
  def send_notification(method:, params: nil)
    uri = build_uri
    http = build_http_client(uri)

    request = build_notification_request(uri, method, params)

    @logger.debug "[McpStreamableHttpService] Sending notification: #{method}"

    begin
      response = http.request(request)
      # Notifications may return 202 Accepted or similar
      response.code.to_i.between?(200, 299)
    rescue StandardError => e
      @logger.warn "[McpStreamableHttpService] Notification failed: #{e.message}"
      false
    end
  end

  def build_uri
    url = @server.capabilities&.dig("url") || @server.env&.dig("url")
    raise ConnectionError, "No URL configured for HTTP MCP server" unless url.present?

    # Streamable HTTP uses a single endpoint (the base URL)
    URI(url)
  end

  def build_http_client(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 60
    http.open_timeout = 10

    # For SSE, we need to handle chunked responses
    http.keep_alive_timeout = 30

    http
  end

  def build_post_request(uri, method, params)
    request = Net::HTTP::Post.new(uri)
    apply_common_headers(request)
    request["Accept"] = "application/json, text/event-stream"

    mcp_request = {
      jsonrpc: "2.0",
      id: generate_request_id,
      method: method
    }
    mcp_request[:params] = params if params.present?

    # Validate not a batch request (MCP 2025-06-18 doesn't support batching)
    McpProtocolService.validate_not_batch(mcp_request)

    request.body = mcp_request.to_json
    request
  end

  def build_notification_request(uri, method, params)
    request = Net::HTTP::Post.new(uri)
    apply_common_headers(request)

    # Notifications don't have an ID
    notification = {
      jsonrpc: "2.0",
      method: method
    }
    notification[:params] = params if params.present?

    request.body = notification.to_json
    request
  end

  def apply_common_headers(request)
    request["Content-Type"] = "application/json"
    request["MCP-Protocol-Version"] = MCP_PROTOCOL_VERSION

    # Include session ID if we have one
    request["MCP-Session-ID"] = @session_id if @session_id.present?

    # Apply authorization
    inject_authorization(request)
  end

  def inject_authorization(request)
    case @server.auth_type
    when "oauth2"
      inject_oauth_token(request)
    when "api_key"
      inject_api_key(request)
    else
      if @server.env&.dig("authorization")
        request["Authorization"] = @server.env["authorization"]
      end
    end
  end

  def inject_oauth_token(request)
    oauth_service = McpOauthService.new(@server)
    access_token = oauth_service.get_valid_access_token

    if access_token.present?
      token_type = @server.oauth_token_type || "Bearer"
      request["Authorization"] = "#{token_type} #{access_token}"
    end
  rescue McpOauthService::TokenRefreshError => e
    @logger.warn "[McpStreamableHttpService] OAuth token unavailable: #{e.message}"
  end

  def inject_api_key(request)
    api_key = @server.env&.dig("api_key") || @server.env&.dig("API_KEY")
    return unless api_key.present?

    header_name = @server.env&.dig("api_key_header") || "Authorization"
    header_prefix = @server.env&.dig("api_key_prefix") || "Bearer"

    if header_name.casecmp("authorization").zero?
      request["Authorization"] = "#{header_prefix} #{api_key}"
    else
      request[header_name] = api_key
    end
  end

  def parse_response(response)
    content_type = response["Content-Type"] || ""
    headers = response.to_hash.transform_values(&:first)

    case response.code.to_i
    when 200..299
      if content_type.include?("text/event-stream")
        # Handle SSE response (may contain multiple events)
        parse_sse_body(response.body, headers)
      else
        # Standard JSON response
        parse_json_response(response.body, headers)
      end
    when 401
      handle_auth_failure(response)
    when 404
      { success: false, error: "Endpoint not found", code: 404, headers: headers }
    else
      { success: false, error: "HTTP error #{response.code}: #{response.body.truncate(500)}", code: response.code.to_i, headers: headers }
    end
  end

  def parse_json_response(body, headers)
    result = JSON.parse(body)

    if result["error"]
      {
        success: false,
        error: result["error"]["message"] || result["error"].to_s,
        error_code: result["error"]["code"],
        headers: headers
      }
    else
      {
        success: true,
        result: result["result"],
        id: result["id"],
        headers: headers
      }
    end
  rescue JSON::ParserError => e
    { success: false, error: "Invalid JSON response: #{e.message}", headers: headers }
  end

  def parse_sse_body(body, headers)
    events = []
    current_event = { type: nil, data: "" }

    body.each_line do |line|
      line = line.strip

      if line.empty?
        # End of event
        if current_event[:data].present?
          events << process_sse_event(current_event)
          current_event = { type: nil, data: "" }
        end
      elsif line.start_with?("event:")
        current_event[:type] = line.sub("event:", "").strip
      elsif line.start_with?("data:")
        data_part = line.sub("data:", "").strip
        current_event[:data] += current_event[:data].empty? ? data_part : "\n#{data_part}"
      elsif line.start_with?("id:")
        current_event[:id] = line.sub("id:", "").strip
      end
    end

    # Process any remaining event
    if current_event[:data].present?
      events << process_sse_event(current_event)
    end

    # Return the last result event or all events
    result_event = events.reverse.find { |e| e[:type] == "message" || e[:result].present? }

    if result_event
      { success: true, result: result_event[:result], events: events, headers: headers }
    elsif events.any?
      { success: true, events: events, headers: headers }
    else
      { success: false, error: "No events in SSE response", headers: headers }
    end
  end

  def process_sse_event(event)
    parsed = JSON.parse(event[:data])
    {
      type: event[:type] || "message",
      id: event[:id],
      result: parsed["result"],
      error: parsed["error"],
      method: parsed["method"],
      params: parsed["params"]
    }
  rescue JSON::ParserError
    { type: event[:type], raw: event[:data] }
  end

  def handle_sse_response(response)
    unless response.code.to_i == 200
      raise ProtocolError, "SSE connection failed: #{response.code}"
    end

    content_type = response["Content-Type"] || ""
    unless content_type.include?("text/event-stream")
      raise ProtocolError, "Expected text/event-stream, got #{content_type}"
    end

    current_event = { type: nil, data: "" }

    response.read_body do |chunk|
      chunk.each_line do |line|
        line = line.strip

        if line.empty?
          if current_event[:data].present?
            event = process_sse_event(current_event)
            yield event
            current_event = { type: nil, data: "" }
          end
        elsif line.start_with?("event:")
          current_event[:type] = line.sub("event:", "").strip
        elsif line.start_with?("data:")
          data_part = line.sub("data:", "").strip
          current_event[:data] += current_event[:data].empty? ? data_part : "\n#{data_part}"
        elsif line.start_with?("id:")
          current_event[:id] = line.sub("id:", "").strip
        end
      end
    end
  end

  def handle_auth_failure(response)
    # If OAuth, try refreshing token
    if @server.auth_type == "oauth2" && !@auth_retry_attempted
      @auth_retry_attempted = true

      begin
        McpOauthService.new(@server).refresh_token!
        @server.reload
        # Caller should retry the request
        { success: false, error: "Token refreshed - retry request", retry: true }
      rescue McpOauthService::TokenRefreshError => e
        { success: false, error: "Authorization failed: #{e.message}", code: 401 }
      end
    else
      { success: false, error: "Unauthorized: #{response.body.truncate(500)}", code: 401 }
    end
  end

  def generate_request_id
    SecureRandom.uuid
  end

  def client_capabilities
    {
      roots: { listChanged: true },
      sampling: {}
    }
  end
end

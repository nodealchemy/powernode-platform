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

    mcp_request = build_mcp_request
    stdin_data = "#{mcp_request.to_json}\n"

    @logger.debug "[McpSyncExecutionService] Executing stdio command: #{@server.command}"

    # Build environment
    env = (@server.env || {}).transform_keys(&:to_s)

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

    # Add any auth headers from server config
    if @server.env&.dig('authorization')
      request['Authorization'] = @server.env['authorization']
    end

    mcp_request = build_mcp_request
    request.body = mcp_request.to_json

    @logger.debug "[McpSyncExecutionService] Executing HTTP request to: #{uri}"

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
      { success: false, error: "HTTP error #{response.code}: #{response.body.truncate(500)}" }
    end
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
end

# frozen_string_literal: true

# Service for executing MCP prompts
# Handles prompts/get and prompts/list protocol calls
class McpPromptService
  def initialize(server:, account:)
    @server = server
    @account = account
    @logger = Rails.logger
  end

  # Execute a prompt by name with arguments
  def execute_prompt(prompt_name, arguments = {})
    @logger.info "[McpPromptService] Executing prompt: #{prompt_name}"

    begin
      mcp_request = {
        jsonrpc: '2.0',
        id: SecureRandom.uuid,
        method: 'prompts/get',
        params: {
          name: prompt_name,
          arguments: arguments
        }
      }

      response = send_mcp_request(mcp_request)

      if response[:error]
        error_message = response[:error][:message] || response[:error]['message'] || 'Unknown error'
        { success: false, error: error_message }
      else
        result = response[:result] || {}
        {
          success: true,
          messages: result['messages'] || result[:messages] || [],
          description: result['description'] || result[:description]
        }
      end
    rescue StandardError => e
      @logger.error "[McpPromptService] Failed to execute prompt: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # List available prompts from the server
  def list_prompts
    @logger.info "[McpPromptService] Listing prompts"

    begin
      mcp_request = {
        jsonrpc: '2.0',
        id: SecureRandom.uuid,
        method: 'prompts/list',
        params: {}
      }

      response = send_mcp_request(mcp_request)

      if response[:error]
        { success: false, error: response[:error][:message] || 'Unknown error' }
      else
        prompts = response[:result]&.dig('prompts') || response[:result]&.dig(:prompts) || []
        { success: true, prompts: prompts }
      end
    rescue StandardError => e
      @logger.error "[McpPromptService] Failed to list prompts: #{e.message}"
      { success: false, error: e.message }
    end
  end

  private

  def send_mcp_request(request)
    case @server.connection_type
    when 'http'
      send_http_request(request)
    when 'stdio'
      send_stdio_request(request)
    when 'websocket'
      send_websocket_request(request)
    else
      { error: { message: "Unsupported connection type: #{@server.connection_type}" } }
    end
  end

  def send_http_request(request)
    require 'net/http'

    url = @server.capabilities&.dig('url') || @server.env&.dig('url')
    raise "No URL configured for HTTP MCP server" unless url

    # Use the appropriate endpoint based on method
    endpoint = case request[:method]
               when 'prompts/get' then '/prompts/get'
               when 'prompts/list' then '/prompts/list'
               else '/mcp'
               end

    uri = URI("#{url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.read_timeout = 30

    http_request = Net::HTTP::Post.new(uri)
    http_request['Content-Type'] = 'application/json'
    http_request['Accept'] = 'application/json'

    if @server.env&.dig('authorization')
      http_request['Authorization'] = @server.env['authorization']
    end

    http_request.body = request.to_json

    response = http.request(http_request)
    JSON.parse(response.body).deep_symbolize_keys
  rescue JSON::ParserError => e
    { error: { message: "Invalid JSON response: #{e.message}" } }
  end

  def send_stdio_request(request)
    require 'open3'

    env = (@server.env || {}).transform_keys(&:to_s)

    stdout, stderr, status = Open3.capture3(
      env,
      @server.command,
      *Array(@server.args),
      stdin_data: "#{request.to_json}\n"
    )

    unless status.success?
      return { error: { message: "MCP process failed: #{stderr.truncate(500)}" } }
    end

    # Parse the last valid JSON response
    stdout.strip.split("\n").reverse_each do |line|
      next if line.strip.empty?

      begin
        parsed = JSON.parse(line)
        return parsed.deep_symbolize_keys if parsed.key?('result') || parsed.key?('error')
      rescue JSON::ParserError
        next
      end
    end

    { error: { message: 'No valid response from MCP server' } }
  end

  def send_websocket_request(request)
    # WebSocket requires persistent connection - fall back to HTTP if available
    if @server.capabilities&.dig('http_fallback_url')
      original_url = @server.capabilities['url']
      @server.capabilities['url'] = @server.capabilities['http_fallback_url']
      result = send_http_request(request)
      @server.capabilities['url'] = original_url
      result
    else
      { error: { message: "WebSocket connection not available for prompt execution" } }
    end
  end
end

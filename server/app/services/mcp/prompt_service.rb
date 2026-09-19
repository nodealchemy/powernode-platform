# frozen_string_literal: true

# Service for executing MCP prompts
# Handles prompts/get and prompts/list protocol calls
module Mcp
  class PromptService
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
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "prompts/get",
        params: {
          name: prompt_name,
          arguments: arguments
        }
      }

      response = send_mcp_request(mcp_request)

      if response[:error]
        error_message = response[:error][:message] || response[:error]["message"] || "Unknown error"
        { success: false, error: error_message }
      else
        result = response[:result] || {}
        {
          success: true,
          messages: result["messages"] || result[:messages] || [],
          description: result["description"] || result[:description]
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
        jsonrpc: "2.0",
        id: SecureRandom.uuid,
        method: "prompts/list",
        params: {}
      }

      response = send_mcp_request(mcp_request)

      if response[:error]
        { success: false, error: response[:error][:message] || "Unknown error" }
      else
        prompts = response[:result]&.dig("prompts") || response[:result]&.dig(:prompts) || []
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
    when "http"
      send_http_request(request)
    when "stdio"
      send_stdio_request(request)
    when "websocket"
      send_websocket_request(request)
    else
      { error: { message: "Unsupported connection type: #{@server.connection_type}" } }
    end
  end

  def send_http_request(request)
    require "net/http"

    url = @server.capabilities&.dig("url") || @server.env&.dig("url")
    raise "No URL configured for HTTP MCP server" unless url

    # Use the appropriate endpoint based on method
    endpoint = case request[:method]
    when "prompts/get" then "/prompts/get"
    when "prompts/list" then "/prompts/list"
    else "/mcp"
    end

    uri = URI("#{url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = 30

    http_request = Net::HTTP::Post.new(uri)
    http_request["Content-Type"] = "application/json"
    http_request["Accept"] = "application/json"

    if @server.env&.dig("authorization")
      http_request["Authorization"] = @server.env["authorization"]
    end

    http_request.body = request.to_json

    response = http.request(http_request)
    JSON.parse(response.body).deep_symbolize_keys
  rescue JSON::ParserError => e
    { error: { message: "Invalid JSON response: #{e.message}" } }
  end

  # IMP-176a386fef98: this used to Open3 @server.command/args/env directly
  # with NO validation at all (no command whitelist, no argv inline-code
  # check, no env sanitization) and spawn @server.command as a bare STRING
  # (shell-injection risk when args is empty), inheriting this Rails
  # process's full environment. Routed through
  # Mcp::SecurityService.validate_stdio_server! for early, no-network-hop
  # refusal of an obviously bad config (unchanged since then).
  #
  # IMP-abda86fb39be (MCP isolation Phase 0 T1): actual EXECUTION no
  # longer happens here. Once validated, the request goes to
  # Mcp::WorkerStdioClient, which POSTs it to the worker's own hardened
  # spawn_stdio (see that file's comment for the full data flow and the
  # tenancy/error-mapping reasoning). Mcp::WorkerStdioClient.execute's
  # return contract is DELIBERATELY identical to what this method used to
  # build by hand below (a symbolized `{result:}`/`{error:{message:}}`
  # Hash) — so it's returned as-is, unchanged shape for this method's own
  # callers (#execute_prompt/#list_prompts). A worker-side timeout now
  # arrives as `{error:{message: "...exceeded Ns..."}}` here (handled by
  # the `if response[:error]` branch in #execute_prompt/#list_prompts)
  # rather than a raised Mcp::SecurityService::StdioTimeoutError caught by
  # their outer rescue — same final {success:false, error: <same text>}
  # result, one branch earlier. A worker-unreachable/5xx failure is a
  # genuinely NEW failure mode (execution used to be in-process) and is
  # NOT translated here: WorkerTransport::HttpError/TimeoutError/
  # ConnectionError (all StandardError) propagate to those methods'
  # existing outer `rescue StandardError` unchanged.
  def send_stdio_request(request)
    server_hash = {
      "command" => @server.command,
      "args" => @server.args,
      "env" => @server.env,
      "capabilities" => @server.capabilities
    }

    begin
      Mcp::SecurityService.validate_stdio_server!(server_hash)
    rescue Mcp::SecurityService::CommandNotAllowedError, Mcp::SecurityService::EnvironmentViolationError => e
      @logger.error "[McpPromptService] Security violation: #{e.message}"
      return { error: { message: "Security error: #{e.message}" } }
    end

    Mcp::WorkerStdioClient.execute(account_id: @account.id, server: server_hash, mcp_request: request)
  end

  def send_websocket_request(request)
    # WebSocket requires persistent connection - fall back to HTTP if available
    if @server.capabilities&.dig("http_fallback_url")
      original_url = @server.capabilities["url"]
      @server.capabilities["url"] = @server.capabilities["http_fallback_url"]
      result = send_http_request(request)
      @server.capabilities["url"] = original_url
      result
    else
      { error: { message: "WebSocket connection not available for prompt execution" } }
    end
  end
  end
end

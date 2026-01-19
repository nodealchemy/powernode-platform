# frozen_string_literal: true

module Devops
  class McpServerExecutor < BaseExecutor
    # Execute an MCP server tool call
    def perform_execution(input)
      tool_name = input[:tool] || input[:tool_name]
      tool_arguments = input[:arguments] || input[:params] || {}

      raise ConfigurationError, "tool name is required" unless tool_name.present?

      validate_tool!(tool_name)

      with_retry(max_attempts: 2) do
        result = call_mcp_tool(tool_name, tool_arguments)

        {
          success: true,
          tool: tool_name,
          result: result,
          server_name: server_name,
          executed_at: Time.current.iso8601
        }
      end
    end

    def perform_connection_test
      # List available tools to test connection
      tools = list_tools

      if tools.present?
        { success: true, message: "Connected to MCP server. #{tools.count} tools available." }
      else
        { success: true, message: "Connected to MCP server. No tools found." }
      end
    rescue StandardError => e
      { success: false, error: "Connection failed: #{e.message}" }
    end

    # List available tools from the MCP server
    def list_tools
      mcp_client.list_tools
    end

    # Get tool schema/definition
    def get_tool_schema(tool_name)
      tools = list_tools
      tools.find { |t| t["name"] == tool_name }
    end

    private

    def server_name
      effective_configuration[:server_name] || instance.name
    end

    def server_type
      effective_configuration[:server_type] || "stdio"
    end

    def server_command
      effective_configuration[:command]
    end

    def server_args
      effective_configuration[:args] || []
    end

    def server_env
      env = effective_configuration[:env] || {}

      # Merge credentials into environment if configured
      if effective_configuration[:credentials_as_env]
        decrypted_credentials.each do |key, value|
          env_key = "MCP_#{key.to_s.upcase}"
          env[env_key] = value
        end
      end

      env
    end

    def validate_tool!(tool_name)
      return unless effective_configuration[:validate_tools]

      tools = list_tools
      tool_names = tools.map { |t| t["name"] }

      unless tool_names.include?(tool_name)
        raise ConfigurationError, "Tool '#{tool_name}' not found. Available: #{tool_names.join(", ")}"
      end
    end

    def call_mcp_tool(tool_name, arguments)
      mcp_client.call_tool(tool_name, arguments)
    end

    def mcp_client
      @mcp_client ||= build_mcp_client
    end

    def build_mcp_client
      case server_type
      when "stdio"
        build_stdio_client
      when "http", "sse"
        build_http_client
      when "websocket"
        build_websocket_client
      else
        raise ConfigurationError, "Unsupported MCP server type: #{server_type}"
      end
    end

    def build_stdio_client
      raise ConfigurationError, "command is required for stdio MCP server" unless server_command.present?

      McpStdioClient.new(
        command: server_command,
        args: server_args,
        env: server_env,
        timeout: read_timeout
      )
    end

    def build_http_client
      url = effective_configuration[:url]
      raise ConfigurationError, "url is required for HTTP MCP server" unless url.present?

      McpHttpClient.new(
        url: url,
        headers: build_mcp_headers,
        timeout: read_timeout
      )
    end

    def build_websocket_client
      url = effective_configuration[:websocket_url] || effective_configuration[:url]
      raise ConfigurationError, "url is required for WebSocket MCP server" unless url.present?

      McpWebSocketClient.new(
        url: url,
        headers: build_mcp_headers,
        timeout: read_timeout
      )
    end

    def build_mcp_headers
      headers = {
        "Content-Type" => "application/json",
        "User-Agent" => "Powernode-MCP-Client/1.0"
      }

      # Add authentication if configured
      if decrypted_credentials[:api_key].present?
        headers["Authorization"] = "Bearer #{decrypted_credentials[:api_key]}"
      end

      headers
    end

    # Simple MCP Client implementations
    # These would typically be in separate files but included here for completeness

    class McpStdioClient
      def initialize(command:, args: [], env: {}, timeout: 30)
        @command = command
        @args = args
        @env = env
        @timeout = timeout
      end

      def list_tools
        send_request("tools/list")["tools"] || []
      end

      def call_tool(name, arguments)
        send_request("tools/call", { name: name, arguments: arguments })
      end

      private

      def send_request(method, params = {})
        request = {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: method,
          params: params
        }

        # Use Open3 to communicate with the process
        stdout, stderr, status = Open3.capture3(
          @env,
          @command,
          *@args,
          stdin_data: request.to_json + "\n"
        )

        unless status.success?
          raise ExecutionError, "MCP server error: #{stderr}"
        end

        JSON.parse(stdout)["result"]
      rescue JSON::ParserError => e
        raise ExecutionError, "Invalid MCP response: #{e.message}"
      end
    end

    class McpHttpClient
      def initialize(url:, headers: {}, timeout: 30)
        @url = url
        @headers = headers
        @timeout = timeout
      end

      def list_tools
        send_request("tools/list")["tools"] || []
      end

      def call_tool(name, arguments)
        send_request("tools/call", { name: name, arguments: arguments })
      end

      private

      def send_request(method, params = {})
        request = {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: method,
          params: params
        }

        response = HTTP
          .timeout(@timeout)
          .headers(@headers)
          .post(@url, json: request)

        unless response.status.success?
          raise ExecutionError, "MCP HTTP error: #{response.status}"
        end

        JSON.parse(response.body.to_s)["result"]
      end
    end

    class McpWebSocketClient
      def initialize(url:, headers: {}, timeout: 30)
        @url = url
        @headers = headers
        @timeout = timeout
      end

      def list_tools
        send_request("tools/list")["tools"] || []
      end

      def call_tool(name, arguments)
        send_request("tools/call", { name: name, arguments: arguments })
      end

      private

      def send_request(method, params = {})
        # WebSocket implementation would require a WebSocket client gem
        # This is a placeholder for the actual implementation
        raise NotImplementedError, "WebSocket MCP client not yet implemented"
      end
    end
  end
end

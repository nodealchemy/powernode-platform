# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for discovering tools from a connected MCP server
  # Uses the MCP protocol's tools/list method to discover available tools
  class McpToolDiscoveryJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 2, backtrace: true

    def execute(server_id)
      log_info("Discovering tools from MCP server", server_id: server_id)

      # Fetch server details from backend API
      response = api_client.get("/api/v1/internal/mcp_servers/#{server_id}")

      unless response[:success]
        log_error("Failed to fetch server details", nil, server_id: server_id)
        return
      end

      server = response[:data][:mcp_server]

      # Verify server is connected
      unless server[:status] == 'connected'
        log_warn("Skipping tool discovery - server not connected",
                 server_id: server_id,
                 status: server[:status])
        return
      end

      # Discover tools via MCP protocol
      result = discover_tools_from_server(server)

      if result[:success]
        tools = result[:tools] || []

        if tools.any?
          # Register discovered tools with backend
          register_response = api_client.post("/api/v1/internal/mcp_servers/#{server_id}/register_tools", {
            tools: tools
          })

          if register_response[:success]
            log_info("MCP tools discovered and registered",
                     server_id: server_id,
                     name: server[:name],
                     tools_count: tools.count)
          else
            log_error("Failed to register discovered tools", nil,
                      server_id: server_id,
                      error: register_response[:error])
          end
        else
          log_info("No tools discovered from MCP server",
                   server_id: server_id,
                   name: server[:name])
        end
      else
        log_error("Tool discovery failed", nil,
                  server_id: server_id,
                  name: server[:name],
                  error: result[:error])
      end
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP tool discovery", e, server_id: server_id)
      raise
    rescue StandardError => e
      log_error("Unexpected error during MCP tool discovery", e, server_id: server_id)
      raise
    end

    private

    def discover_tools_from_server(server)
      case server[:connection_type]
      when 'stdio'
        discover_stdio_tools(server)
      when 'websocket'
        discover_websocket_tools(server)
      when 'http'
        discover_http_tools(server)
      else
        { success: false, error: "Unknown connection type: #{server[:connection_type]}" }
      end
    end

    def discover_stdio_tools(server)
      command = server[:command]
      args = Array(server[:args])

      begin
        require 'open3'

        # Build MCP tools/list request
        list_request = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'tools/list',
          params: {}
        }

        stdin_data = list_request.to_json
        stdout, stderr, status = Open3.capture3(
          server[:env] || {},
          command,
          *args,
          stdin_data: stdin_data
        )

        if status.success? || stdout.present?
          response = parse_tools_response(stdout)
          if response[:error]
            { success: false, error: response[:error][:message] }
          else
            tools = (response[:result]&.dig(:tools) || response[:result] || []).map do |tool|
              normalize_tool(tool)
            end
            { success: true, tools: tools }
          end
        else
          { success: false, error: "Process failed: #{stderr.presence || 'Unknown error'}" }
        end
      rescue Errno::ENOENT
        { success: false, error: "Command not found: #{command}" }
      rescue StandardError => e
        { success: false, error: "Discovery error: #{e.message}" }
      end
    end

    def discover_websocket_tools(server)
      { success: false, tools: [], error: 'WebSocket transport not yet supported for tool discovery' }
    end

    def discover_http_tools(server)
      require 'net/http'

      begin
        uri = URI("#{server[:url]}/tools/list")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 15

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'tools/list',
          params: {}
        }.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          result = JSON.parse(response.body)
          if result['error']
            { success: false, error: result['error']['message'] }
          else
            tools = (result['result']&.dig('tools') || result['result'] || []).map do |tool|
              normalize_tool(tool)
            end
            { success: true, tools: tools }
          end
        else
          { success: false, error: "HTTP error: #{response.code}" }
        end
      rescue StandardError => e
        { success: false, error: "HTTP request failed: #{e.message}" }
      end
    end

    def parse_tools_response(stdout)
      lines = stdout.strip.split("\n")
      lines.reverse_each do |line|
        next if line.strip.empty?

        begin
          parsed = JSON.parse(line)
          return deep_symbolize_keys(parsed) if parsed['result'] || parsed['error']
        rescue JSON::ParserError
          next
        end
      end

      { error: { message: 'No valid MCP response received' } }
    end

    def normalize_tool(tool)
      # Normalize tool data to match our schema
      {
        name: tool['name'] || tool[:name],
        description: tool['description'] || tool[:description],
        input_schema: tool['inputSchema'] || tool['input_schema'] || tool[:inputSchema] || tool[:input_schema] || {}
      }
    end

    def deep_symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = case value
                             when Hash then deep_symbolize_keys(value)
                             when Array then value.map { |v| deep_symbolize_keys(v) }
                             else value
                             end
      end
    end
  end
end

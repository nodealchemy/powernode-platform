# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for managing MCP server connections asynchronously
  # Handles both connect and disconnect actions
  class McpServerConnectionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(server_id, options = {})
      action = options['action'] || options[:action] || 'connect'

      log_info("MCP server #{action} job started", server_id: server_id, action: action)

      # Fetch server details from backend API
      response = api_client.get("/api/v1/internal/mcp_servers/#{server_id}")

      unless response[:success]
        log_error('Failed to fetch server details', nil, server_id: server_id)
        return
      end

      server = response[:data][:mcp_server]

      case action
      when 'connect'
        handle_connect(server)
      when 'disconnect'
        handle_disconnect(server)
      else
        log_error('Unknown action', nil, server_id: server_id, action: action)
      end
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP server #{options['action'] || 'connect'}", e, server_id: server_id)
      raise
    rescue StandardError => e
      log_error('Unexpected error during MCP server connection', e, server_id: server_id)
      raise
    end

    private

    def handle_connect(server)
      log_info('Connecting to MCP server', server_id: server[:id], name: server[:name])

      result = establish_connection(server)

      if result[:success]
        # Update server status to connected
        api_client.patch("/api/v1/internal/mcp_servers/#{server[:id]}", {
                           status: 'connected',
                           capabilities: result[:capabilities],
                           last_connected_at: Time.current.iso8601
                         })

        log_info('MCP server connected successfully',
                 server_id: server[:id],
                 name: server[:name],
                 capabilities: result[:capabilities])

        # Trigger tool discovery
        McpToolDiscoveryJob.perform_async(server[:id])
      else
        # Update server status to error
        api_client.patch("/api/v1/internal/mcp_servers/#{server[:id]}", {
                           status: 'error',
                           last_error: result[:error]
                         })

        log_error('MCP server connection failed', nil,
                  server_id: server[:id],
                  name: server[:name],
                  error: result[:error])
      end
    end

    def handle_disconnect(server)
      log_info('Disconnecting from MCP server', server_id: server[:id], name: server[:name])

      # Perform any cleanup needed for the connection type
      cleanup_connection(server)

      # Update server status
      api_client.patch("/api/v1/internal/mcp_servers/#{server[:id]}", {
                         status: 'disconnected'
                       })

      log_info('MCP server disconnected', server_id: server[:id], name: server[:name])
    end

    def establish_connection(server)
      case server[:connection_type]
      when 'stdio'
        establish_stdio_connection(server)
      when 'websocket'
        establish_websocket_connection(server)
      when 'http'
        establish_http_connection(server)
      else
        { success: false, error: "Unknown connection type: #{server[:connection_type]}" }
      end
    end

    def establish_stdio_connection(server)
      # For stdio connections, we verify the command exists and can respond to initialize
      command = server[:command]
      args = Array(server[:args])
      env = server[:env] || {}

      # Security validation - command whitelist and environment sanitization
      begin
        validated = McpSecurityService.validate_stdio_execution!(
          command: command,
          env: env,
          allow_extended: server.dig(:capabilities, 'allow_extended_commands') == true,
          strict_env: server.dig(:capabilities, 'strict_environment') == true
        )
      rescue McpSecurityService::CommandNotAllowedError => e
        log_error('Security violation - command blocked', nil, server_id: server[:id], error: e.message)
        return { success: false, error: "Security error: #{e.message}" }
      rescue McpSecurityService::EnvironmentViolationError => e
        log_error('Security violation - environment blocked', nil, server_id: server[:id], error: e.message)
        return { success: false, error: "Security error: #{e.message}" }
      end

      begin
        require 'open3'

        # Build MCP initialize request
        init_request = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'initialize',
          params: {
            protocolVersion: '2025-06-18',
            capabilities: {
              roots: { listChanged: true }
            },
            clientInfo: {
              name: 'Powernode Worker',
              version: '1.0.0'
            }
          }
        }

        stdin_data = init_request.to_json
        # Use sanitized environment
        sanitized_env = validated[:env].transform_keys(&:to_s)

        stdout, stderr, status = Open3.capture3(
          sanitized_env,
          command,
          *args,
          stdin_data: stdin_data
        )

        if status.success? || stdout.present?
          # Parse the response to extract capabilities
          capabilities = parse_init_response(stdout)
          {
            success: true,
            capabilities: {
              'tools' => capabilities.dig('capabilities', 'tools').present?,
              'resources' => capabilities.dig('capabilities', 'resources').present?,
              'prompts' => capabilities.dig('capabilities', 'prompts').present?,
              'logging' => capabilities.dig('capabilities', 'logging').present?,
              'serverInfo' => capabilities['serverInfo']
            }
          }
        else
          { success: false, error: "Process failed: #{stderr.presence || 'Unknown error'}" }
        end
      rescue Errno::ENOENT
        { success: false, error: "Command not found: #{command}" }
      rescue StandardError => e
        { success: false, error: "Connection error: #{e.message}" }
      end
    end

    def establish_websocket_connection(server)
      # WebSocket connections for MCP require persistent connections
      # which are not suitable for a background job context.
      # WebSocket-based MCP servers should use the real-time connection manager.
      require 'websocket-client-simple'

      ws_url = server[:url] || server[:websocket_url]

      unless ws_url.present?
        return { success: false, error: 'WebSocket URL not configured' }
      end

      capabilities = nil
      error_message = nil
      connected = false
      init_response_received = false

      begin
        Timeout.timeout(15) do
          ws = WebSocket::Client::Simple.connect(ws_url)

          ws.on :open do
            connected = true
            # Send MCP initialize request
            init_request = {
              jsonrpc: '2.0',
              id: SecureRandom.uuid,
              method: 'initialize',
              params: {
                protocolVersion: '2025-06-18',
                capabilities: { roots: { listChanged: true } },
                clientInfo: { name: 'Powernode Worker', version: '1.0.0' }
              }
            }
            ws.send(init_request.to_json)
          end

          ws.on :message do |msg|
            begin
              response = JSON.parse(msg.data)
              if response['result']
                capabilities = {
                  'tools' => response['result'].dig('capabilities', 'tools').present?,
                  'resources' => response['result'].dig('capabilities', 'resources').present?,
                  'prompts' => response['result'].dig('capabilities', 'prompts').present?,
                  'logging' => response['result'].dig('capabilities', 'logging').present?,
                  'serverInfo' => response['result']['serverInfo']
                }
                init_response_received = true
              elsif response['error']
                error_message = response['error']['message']
              end
            rescue JSON::ParserError
              error_message = 'Invalid JSON response from server'
            end
          end

          ws.on :error do |e|
            error_message = e.message
          end

          # Wait for initialization response
          start_time = Time.current
          while !init_response_received && error_message.nil? && (Time.current - start_time) < 10
            sleep 0.1
          end

          ws.close if ws.open?
        end
      rescue Timeout::Error
        error_message = 'WebSocket connection timeout'
      rescue LoadError
        # websocket-client-simple gem not available
        log_warn('WebSocket gem not available, WebSocket connections not supported',
                 server_id: server[:id])
        return {
          success: false,
          error: 'WebSocket support requires websocket-client-simple gem'
        }
      rescue StandardError => e
        error_message = "WebSocket error: #{e.message}"
      end

      if init_response_received && capabilities
        { success: true, capabilities: capabilities }
      else
        { success: false, error: error_message || 'Failed to initialize WebSocket connection' }
      end
    end

    def establish_http_connection(server)
      # HTTP connection verification
      require 'net/http'

      begin
        uri = URI("#{server[:url]}/initialize")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'

        init_request = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'initialize',
          params: {
            protocolVersion: '2025-06-18',
            clientInfo: { name: 'Powernode Worker', version: '1.0.0' }
          }
        }
        request.body = init_request.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          result = JSON.parse(response.body)
          {
            success: true,
            capabilities: result['result']&.dig('capabilities') || {}
          }
        else
          { success: false, error: "HTTP error: #{response.code}" }
        end
      rescue StandardError => e
        { success: false, error: "HTTP connection failed: #{e.message}" }
      end
    end

    def cleanup_connection(_server)
      # Cleanup logic for persistent connections
      # For stdio connections, there's nothing to clean up
      # WebSocket connections would need to be closed
      true
    end

    def parse_init_response(stdout)
      lines = stdout.strip.split("\n")
      lines.reverse_each do |line|
        next if line.strip.empty?

        begin
          parsed = JSON.parse(line)
          return parsed['result'] if parsed['result']
        rescue JSON::ParserError
          next
        end
      end

      {}
    end
  end
end

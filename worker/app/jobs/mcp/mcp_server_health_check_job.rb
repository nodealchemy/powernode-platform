# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for performing periodic health checks on MCP servers
  # Can check a single server or all connected servers
  class McpServerHealthCheckJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 2, backtrace: true

    def execute(server_id = nil)
      if server_id
        check_single_server(server_id)
      else
        check_all_servers
      end
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP health check", e, server_id: server_id)
      raise
    rescue StandardError => e
      log_error("Unexpected error during MCP health check", e, server_id: server_id)
      raise
    end

    private

    def check_all_servers
      log_info("Starting health check for all connected MCP servers")

      # Fetch all connected servers
      response = api_client.get("/api/v1/internal/mcp_servers?status=connected")

      unless response[:success]
        log_error("Failed to fetch connected servers")
        return
      end

      servers = response[:data][:mcp_servers] || []

      if servers.empty?
        log_info("No connected MCP servers to check")
        return
      end

      log_info("Checking health of #{servers.count} MCP server(s)")

      servers.each do |server|
        # Queue individual health checks to distribute load
        McpServerHealthCheckJob.perform_async(server[:id])
      end

      log_info("Queued health checks for #{servers.count} MCP server(s)")
    end

    def check_single_server(server_id)
      log_info("Checking health of MCP server", server_id: server_id)

      # Fetch server details
      response = api_client.get("/api/v1/internal/mcp_servers/#{server_id}")

      unless response[:success]
        log_error("Failed to fetch server details", nil, server_id: server_id)
        return
      end

      server = response[:data][:mcp_server]

      # Skip if server is not connected
      unless server[:status] == 'connected'
        log_info("Skipping health check - server not connected",
                 server_id: server_id,
                 status: server[:status])
        return
      end

      # Perform the health check
      started_at = Time.current
      result = ping_server(server)
      latency_ms = ((Time.current - started_at) * 1000).to_i

      # Report results to backend
      api_client.post("/api/v1/internal/mcp_servers/#{server_id}/health_result", {
        healthy: result[:healthy],
        latency_ms: latency_ms
      })

      if result[:healthy]
        log_info("MCP server health check passed",
                 server_id: server_id,
                 name: server[:name],
                 latency_ms: latency_ms)
      else
        log_warn("MCP server health check failed",
                 server_id: server_id,
                 name: server[:name],
                 error: result[:error])
      end
    end

    def ping_server(server)
      case server[:connection_type]
      when 'stdio'
        ping_stdio_server(server)
      when 'websocket'
        ping_websocket_server(server)
      when 'http'
        ping_http_server(server)
      else
        { healthy: false, error: "Unknown connection type: #{server[:connection_type]}" }
      end
    end

    def ping_stdio_server(server)
      # For stdio servers, we send a ping request
      command = server[:command]
      args = Array(server[:args])

      begin
        require 'open3'

        # Send MCP ping request
        ping_request = {
          jsonrpc: '2.0',
          id: SecureRandom.uuid,
          method: 'ping',
          params: {}
        }

        stdin_data = ping_request.to_json
        stdout, _stderr, status = Open3.capture3(
          server[:env] || {},
          command,
          *args,
          stdin_data: stdin_data
        )

        # Consider it healthy if we get any valid JSON response
        if status.success? || stdout.present?
          begin
            JSON.parse(stdout.strip.split("\n").last)
            { healthy: true }
          rescue JSON::ParserError
            { healthy: false, error: 'Invalid JSON response' }
          end
        else
          { healthy: false, error: 'Process failed' }
        end
      rescue Errno::ENOENT
        { healthy: false, error: "Command not found: #{command}" }
      rescue StandardError => e
        { healthy: false, error: e.message }
      end
    end

    def ping_websocket_server(server)
      require 'net/http'

      begin
        uri = URI.parse(server[:url].sub('ws://', 'http://').sub('wss://', 'https://'))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 5
        http.open_timeout = 5

        response = Net::HTTP.get_response(uri)
        { healthy: response.code.to_i < 500 }
      rescue StandardError => e
        { healthy: false, error: e.message }
      end
    end

    def ping_http_server(server)
      require 'net/http'

      begin
        uri = URI("#{server[:url]}/ping")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 5
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = { jsonrpc: '2.0', id: SecureRandom.uuid, method: 'ping' }.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          { healthy: true }
        else
          { healthy: false, error: "HTTP #{response.code}" }
        end
      rescue StandardError => e
        { healthy: false, error: e.message }
      end
    end
  end
end

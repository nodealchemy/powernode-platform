# frozen_string_literal: true

require_relative '../base_job'

module Mcp
  # Job for executing MCP tools asynchronously
  # This job handles the actual execution of MCP tools via the MCP protocol
  class McpToolExecutionJob < BaseJob
    sidekiq_options queue: 'mcp', retry: 3, backtrace: true

    def execute(execution_id)
      log_info("Starting MCP tool execution", execution_id: execution_id)

      # Fetch execution details from backend API
      response = api_client.get("/api/v1/internal/mcp_tool_executions/#{execution_id}")

      unless response[:success]
        log_error("Failed to fetch execution details", nil, execution_id: execution_id)
        return
      end

      execution_data = response[:data][:mcp_tool_execution]
      tool = execution_data[:mcp_tool]
      server = tool[:mcp_server]

      # Update status to running
      api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
        status: 'running'
      })

      # Execute the tool via MCP protocol
      started_at = Time.current
      result = execute_mcp_tool(server, tool, execution_data[:parameters])
      duration_ms = ((Time.current - started_at) * 1000).to_i

      # Update execution with result
      if result[:success]
        api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
          status: 'completed',
          result: result[:output],
          execution_time_ms: duration_ms
        })

        log_info("MCP tool execution completed",
                 execution_id: execution_id,
                 tool_name: tool[:name],
                 duration_ms: duration_ms)
      else
        api_client.patch("/api/v1/internal/mcp_tool_executions/#{execution_id}", {
          status: 'failed',
          error_message: result[:error],
          execution_time_ms: duration_ms
        })

        log_error("MCP tool execution failed", nil,
                  execution_id: execution_id,
                  tool_name: tool[:name],
                  error: result[:error])
      end
    rescue BackendApiClient::ApiError => e
      log_error("API error during MCP tool execution", e, execution_id: execution_id)
      raise
    rescue StandardError => e
      log_error("Unexpected error during MCP tool execution", e, execution_id: execution_id)
      raise
    end

    private

    def execute_mcp_tool(server, tool, parameters)
      case server[:connection_type]
      when 'stdio'
        execute_stdio_tool(server, tool, parameters)
      when 'websocket'
        execute_websocket_tool(server, tool, parameters)
      when 'http'
        execute_http_tool(server, tool, parameters)
      else
        { success: false, error: "Unknown connection type: #{server[:connection_type]}" }
      end
    end

    def execute_stdio_tool(server, tool, parameters)
      # Build the MCP tools/call request
      mcp_request = build_mcp_request('tools/call', {
        name: tool[:name],
        arguments: parameters
      })

      # Execute the command with the request piped to stdin
      command = server[:command]
      args = Array(server[:args])

      begin
        require 'open3'

        stdin_data = mcp_request.to_json
        stdout, stderr, status = Open3.capture3(
          server[:env] || {},
          command,
          *args,
          stdin_data: stdin_data
        )

        if status.success?
          response = parse_mcp_response(stdout)
          if response[:error]
            { success: false, error: response[:error][:message] }
          else
            { success: true, output: response[:result] }
          end
        else
          { success: false, error: "Process exited with code #{status.exitstatus}: #{stderr}" }
        end
      rescue Errno::ENOENT
        { success: false, error: "Command not found: #{command}" }
      rescue StandardError => e
        { success: false, error: "Execution error: #{e.message}" }
      end
    end

    def execute_websocket_tool(server, tool, parameters)
      require 'websocket-client-simple'
      require 'timeout'

      ws_url = server[:url] || server[:websocket_url]
      return { success: false, error: 'No WebSocket URL configured for server' } unless ws_url.present?

      # Ensure URL starts with ws:// or wss://
      ws_url = "ws://#{ws_url}" unless ws_url.start_with?('ws://', 'wss://')

      # Generate unique request ID
      request_id = SecureRandom.uuid

      # Build MCP request
      mcp_request = build_mcp_request('tools/call', {
        name: tool[:name],
        arguments: parameters
      })
      mcp_request[:id] = request_id

      # Track state
      response_received = false
      result = nil
      error_message = nil

      # Connection timeout (seconds)
      connection_timeout = server[:connection_timeout] || 10
      # Response timeout (seconds)
      response_timeout = server[:response_timeout] || 60

      begin
        ws = nil
        connected = false
        mutex = Mutex.new
        condition = ConditionVariable.new

        # Create WebSocket connection
        ws = WebSocket::Client::Simple.connect(ws_url) do |client|
          client.on :open do
            log_info('WebSocket connection opened', url: ws_url)
            mutex.synchronize do
              connected = true
              condition.signal
            end
          end

          client.on :message do |msg|
            begin
              data = JSON.parse(msg.data)

              # Check if this is our response (matching request ID)
              if data['id'] == request_id || data['jsonrpc'] == '2.0'
                mutex.synchronize do
                  response_received = true
                  if data['error']
                    error_message = data['error']['message'] || 'Unknown error from MCP server'
                  else
                    result = data['result']
                  end
                  condition.signal
                end
              end
            rescue JSON::ParserError => e
              log_warn("Failed to parse WebSocket message: #{e.message}")
            end
          end

          client.on :error do |e|
            log_error("WebSocket error", e)
            mutex.synchronize do
              error_message ||= "WebSocket error: #{e.message}"
              condition.signal
            end
          end

          client.on :close do |e|
            log_info("WebSocket connection closed", code: e&.code)
            mutex.synchronize do
              error_message ||= 'WebSocket connection closed unexpectedly' unless response_received
              condition.signal
            end
          end
        end

        # Wait for connection with timeout
        Timeout.timeout(connection_timeout) do
          mutex.synchronize do
            condition.wait(mutex) until connected || error_message
          end
        end

        unless connected
          return { success: false, error: error_message || 'Failed to connect to WebSocket server' }
        end

        # Send the MCP request
        log_info('Sending MCP request via WebSocket',
                 tool_name: tool[:name],
                 request_id: request_id)
        ws.send(mcp_request.to_json)

        # Wait for response with timeout
        Timeout.timeout(response_timeout) do
          mutex.synchronize do
            condition.wait(mutex) until response_received || error_message
          end
        end

        # Close the connection
        ws.close if ws

        if error_message
          { success: false, error: error_message }
        elsif result
          { success: true, output: result }
        else
          { success: false, error: 'No response received from MCP server' }
        end

      rescue Timeout::Error
        { success: false, error: "WebSocket operation timed out (connection: #{connection_timeout}s, response: #{response_timeout}s)" }
      rescue Errno::ECONNREFUSED
        { success: false, error: "Connection refused to WebSocket server: #{ws_url}" }
      rescue StandardError => e
        { success: false, error: "WebSocket execution error: #{e.class} - #{e.message}" }
      ensure
        begin
          ws&.close
        rescue StandardError
          # Ignore errors during cleanup
        end
      end
    end

    # Alternative synchronous WebSocket implementation using lower-level API
    def execute_websocket_tool_sync(server, tool, parameters)
      require 'socket'
      require 'websocket'

      ws_url = server[:url] || server[:websocket_url]
      return { success: false, error: 'No WebSocket URL configured for server' } unless ws_url.present?

      uri = URI.parse(ws_url.start_with?('ws') ? ws_url : "ws://#{ws_url}")
      host = uri.host
      port = uri.port || (uri.scheme == 'wss' ? 443 : 80)
      path = uri.path.presence || '/'

      request_id = SecureRandom.uuid
      mcp_request = build_mcp_request('tools/call', {
        name: tool[:name],
        arguments: parameters
      })
      mcp_request[:id] = request_id

      timeout_seconds = server[:response_timeout] || 60

      begin
        # Create TCP socket
        socket = if uri.scheme == 'wss'
                   require 'openssl'
                   tcp = TCPSocket.new(host, port)
                   ctx = OpenSSL::SSL::SSLContext.new
                   ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
                   ssl.sync_close = true
                   ssl.connect
                   ssl
                 else
                   TCPSocket.new(host, port)
                 end

        socket.read_timeout = timeout_seconds
        socket.write_timeout = timeout_seconds if socket.respond_to?(:write_timeout=)

        # Perform WebSocket handshake
        handshake = WebSocket::Handshake::Client.new(url: ws_url)
        socket.write(handshake.to_s)

        # Read handshake response
        while (line = socket.gets)
          handshake << line
          break if handshake.finished?
        end

        unless handshake.valid?
          return { success: false, error: 'WebSocket handshake failed' }
        end

        # Send MCP request as WebSocket frame
        frame = WebSocket::Frame::Outgoing::Client.new(
          data: mcp_request.to_json,
          type: :text,
          version: handshake.version
        )
        socket.write(frame.to_s)

        # Read response
        incoming_frame = WebSocket::Frame::Incoming::Client.new(version: handshake.version)
        result = nil
        error_message = nil

        Timeout.timeout(timeout_seconds) do
          loop do
            data = socket.readpartial(4096)
            incoming_frame << data

            while (frame_data = incoming_frame.next)
              case frame_data.type
              when :text
                begin
                  parsed = JSON.parse(frame_data.data)
                  if parsed['id'] == request_id || parsed['jsonrpc'] == '2.0'
                    if parsed['error']
                      error_message = parsed['error']['message']
                    else
                      result = parsed['result']
                    end
                    break
                  end
                rescue JSON::ParserError
                  next
                end
              when :close
                error_message ||= 'WebSocket closed by server'
                break
              when :ping
                # Respond to ping with pong
                pong = WebSocket::Frame::Outgoing::Client.new(
                  type: :pong,
                  version: handshake.version
                )
                socket.write(pong.to_s)
              end
            end

            break if result || error_message
          end
        end

        if error_message
          { success: false, error: error_message }
        elsif result
          { success: true, output: result }
        else
          { success: false, error: 'No valid response received' }
        end

      rescue Timeout::Error
        { success: false, error: "WebSocket response timeout after #{timeout_seconds} seconds" }
      rescue StandardError => e
        { success: false, error: "WebSocket error: #{e.class} - #{e.message}" }
      ensure
        socket&.close rescue nil
      end
    end

    def execute_http_tool(server, tool, parameters)
      # HTTP tool execution via REST endpoint
      require 'net/http'

      begin
        uri = URI("#{server[:url]}/tools/call")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'

        mcp_request = build_mcp_request('tools/call', {
          name: tool[:name],
          arguments: parameters
        })
        request.body = mcp_request.to_json

        response = http.request(request)

        case response.code.to_i
        when 200..299
          result = JSON.parse(response.body)
          if result['error']
            { success: false, error: result['error']['message'] }
          else
            { success: true, output: result['result'] }
          end
        else
          { success: false, error: "HTTP error: #{response.code} - #{response.body}" }
        end
      rescue StandardError => e
        { success: false, error: "HTTP request failed: #{e.message}" }
      end
    end

    def build_mcp_request(method, params)
      {
        jsonrpc: '2.0',
        id: SecureRandom.uuid,
        method: method,
        params: params
      }
    end

    def parse_mcp_response(json_string)
      # MCP servers may output multiple JSON-RPC responses
      # We need to find the one matching our request
      lines = json_string.strip.split("\n")
      lines.reverse_each do |line|
        next if line.strip.empty?

        begin
          parsed = JSON.parse(line)
          return parsed.transform_keys(&:to_sym) if parsed['result'] || parsed['error']
        rescue JSON::ParserError
          next
        end
      end

      { error: { message: 'No valid MCP response received' } }
    end
  end
end

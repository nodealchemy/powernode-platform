# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class StreamableHttpController < ApplicationController
        include ActionController::Live
        include McpTokenAuthentication

        MCP_PROTOCOL_VERSION = "2025-11-25"
        SESSION_TTL = 24.hours
        SSE_KEEPALIVE_INTERVAL = 30 # seconds
        ALLOWED_WORKSPACE_EVENTS = %w[message_created ai_response_complete agent_joined agent_left mention].freeze

        # Session-level dedup: prevents duplicate SSE events across multiple
        # concurrent stream connections for the same MCP session.
        # Hash<session_token => { mutex: Mutex, ids: Set, last_access: Time }>
        @@sse_dedup_registry = {}
        @@sse_dedup_registry_mutex = Mutex.new

        skip_before_action :authenticate_request
        before_action :set_mcp_headers
        before_action :authenticate_mcp_request
        before_action :track_session_activity

        # POST /api/v1/mcp/message
        # Handles all JSON-RPC 2.0 MCP messages
        # Supports SSE streaming when client sends Accept: text/event-stream
        def message
          body = parse_request_body
          return if performed?

          # MCP 2025-06-18 does not support JSON-RPC batching
          if body.is_a?(Array)
            render_jsonrpc_error(nil, -32600, "JSON-RPC batching is not supported")
            return
          end

          validate_jsonrpc!(body)
          return if performed?

          method = body["method"]
          params = body["params"] || {}
          message_id = body["id"]

          # Notifications (no id) get 202 Accepted
          if message_id.nil?
            handle_notification(method, params)
            return
          end

          # Stream tools/call responses as SSE when client accepts it
          if streaming_accepted? && method == "tools/call"
            handle_streaming_tools_call(params, message_id)
            return
          end

          result = dispatch_method(method, params, message_id)
          return if performed?

          render_jsonrpc_result(message_id, result)
        rescue JSON::ParserError
          render_jsonrpc_error(nil, -32700, "Parse error: invalid JSON")
        rescue ::Mcp::ProtocolService::PermissionDeniedError => e
          render_jsonrpc_error(body&.dig("id"), -32001, e.message)
        rescue ::Mcp::ProtocolService::ToolNotFoundError => e
          render_jsonrpc_error(body&.dig("id"), -32601, e.message)
        rescue ::Mcp::ProtocolService::SchemaValidationError => e
          render_jsonrpc_error(body&.dig("id"), -32602, e.message)
        rescue ArgumentError => e
          render_jsonrpc_error(body&.dig("id"), -32602, e.message)
        rescue StandardError => e
          Rails.logger.error "[MCP StreamableHTTP] Internal error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
          render_jsonrpc_error(body&.dig("id"), -32603, "Internal error: #{e.message}")
        end

        # DELETE /api/v1/mcp/message
        # Terminates an MCP session
        def terminate_session
          session_id = request.headers["Mcp-Session-Id"]
          if session_id.present?
            McpSession.find_by(session_token: session_id)&.revoke!
          end

          head :ok
        end

        # GET /api/v1/mcp/message
        # Opens an SSE stream for push notifications (MCP notifications + workspace events)
        # Agent identity is optional — sessions without agents receive MCP notifications only
        def stream
          session = find_mcp_session
          return head :bad_request unless session

          agent = session.ai_agent

          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"
          response.headers["Connection"] = "keep-alive"

          sse = ActionController::Live::SSE.new(response.stream, retry: 5000)

          # Session channel always subscribed; workspace channels only when agent-bound
          session_channel = "mcp_session:#{session.session_token}"
          all_channels = [session_channel]
          workspace_channel_set = Set.new
          if agent
            ws_channels = workspace_channels_for_agent(agent)
            all_channels += ws_channels
            workspace_channel_set = ws_channels.to_set
          end

          # Send initial connected event
          sse.write({ type: "session/connected", channels: all_channels.size }, event: "open")

          # Subscribe to all channels via ActionCable's adapter-agnostic pubsub
          pubsub = ActionCable.server.pubsub
          callbacks = {}

          # Per-connection dedup: prevents duplicate events within a single SSE
          # connection when the same message arrives via multiple channels
          # (e.g., both mcp_session: and workspace channel).
          dedup = { mutex: Mutex.new, ids: Set.new }

          all_channels.each do |channel|
            is_workspace_channel = workspace_channel_set.include?(channel)

            callback = proc do |raw_message|
              data = JSON.parse(raw_message) rescue next

              if data["jsonrpc"] == "2.0" && data["method"].is_a?(String)
                # MCP JSON-RPC 2.0 notification — spec-compliant event: message
                sse.write(data, event: "message")
              else
                # Workspace event — forward with event type name
                event_type = data["type"] || data[:type]
                next unless ALLOWED_WORKSPACE_EVENTS.include?(event_type.to_s)

                # For workspace channels, only forward if this agent is @mentioned.
                # Checks both structured metadata mentions and text @Name patterns.
                # Structural events (agent_joined/agent_left) pass through unfiltered.
                if is_workspace_channel && %w[message_created ai_response_complete].include?(event_type.to_s)
                  msg = data["message"] || {}
                  mentions = msg.dig("metadata", "mentions") ||
                             msg.dig("content_metadata", "mentions") || []
                  agent_mentioned = false

                  if mentions.any?
                    mentioned_ids = mentions.filter_map { |m| m["id"] || m[:id] }
                    mentioned_names = mentions.filter_map { |m| m["name"] || m[:name] }
                    agent_mentioned = mentioned_ids.include?(agent&.id) ||
                                      mentioned_names.include?(agent&.name)
                  end

                  # Fallback: check for @AgentName in message content (agent-to-agent path)
                  unless agent_mentioned
                    content = (msg["content"] || "").to_s
                    agent_mentioned = agent&.name.present? && content.include?("@#{agent.name}")
                  end

                  next unless agent_mentioned
                end

                # Deduplicate: same message can arrive via session + workspace channels,
                # and also across concurrent SSE connections for the same session.
                # Include event_type in dedup key so ai_response_complete passes through
                # even when message_created was already seen for the same message.
                msg_id = (data["message"].is_a?(Hash) && data["message"]["id"]) || data["message_id"]
                if msg_id.present?
                  dedup_key = "#{event_type}:#{msg_id}"
                  next if sse_dedup_seen?(dedup, dedup_key)
                end

                sse.write(data, event: event_type.to_s)
              end
            end

            callbacks[channel] = callback
            pubsub.subscribe(channel, callback)
          end

          # Keepalive loop — sends pings and refreshes session TTL
          loop do
            sleep SSE_KEEPALIVE_INTERVAL
            sse.write({ type: "ping", timestamp: Time.current.iso8601 }, event: "ping")
            session.touch_activity!
          end
        rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
          # Client disconnected — normal cleanup
        ensure
          # Unsubscribe from all channels
          callbacks&.each do |channel, callback|
            pubsub&.unsubscribe(channel, callback)
          rescue StandardError
            nil
          end
          sse&.close rescue nil
        end

        private

        def set_mcp_headers
          response.set_header("MCP-Protocol-Version", MCP_PROTOCOL_VERSION)
        end

        def track_session_activity
          session_id = request.headers["Mcp-Session-Id"]
          return unless session_id.present?

          McpSession.find_by(session_token: session_id, status: "active")&.touch_activity!
        end

        def parse_request_body
          request.body.rewind
          JSON.parse(request.body.read)
        rescue JSON::ParserError
          render_jsonrpc_error(nil, -32700, "Parse error: invalid JSON")
          nil
        end

        def validate_jsonrpc!(body)
          unless body.is_a?(Hash)
            render_jsonrpc_error(nil, -32600, "Invalid request: expected JSON object")
            return
          end

          unless body["jsonrpc"] == "2.0"
            render_jsonrpc_error(body["id"], -32600, "Invalid request: jsonrpc must be '2.0'")
            return
          end

          unless body["method"].is_a?(String) && body["method"].present?
            render_jsonrpc_error(body["id"], -32600, "Invalid request: method is required")
          end
        end

        def handle_notification(method, _params)
          case method
          when "notifications/initialized", "notifications/cancelled"
            head :accepted
          else
            head :accepted
          end
        end

        def dispatch_method(method, params, message_id)
          case method
          when "initialize"
            handle_initialize(params, message_id)
          when "ping"
            {}
          when "tools/list"
            handle_tools_list(params)
          when "tools/call"
            handle_tools_call(params)
          when "resources/list"
            handle_resources_list(params)
          when "resources/read"
            handle_resources_read(params)
          when "prompts/list"
            handle_prompts_list(params)
          when "prompts/get"
            handle_prompts_get(params)
          else
            render_jsonrpc_error(message_id, -32601, "Method not found: #{method}")
            nil
          end
        end

        # =====================================================================
        # MCP Method Handlers
        # =====================================================================

        def handle_initialize(params, message_id)
          client_version = params["protocolVersion"]
          negotiated = ::Mcp::ProtocolService.negotiate_protocol_version(client_version)

          unless negotiated
            render_jsonrpc_error(message_id, -32602, "Unsupported protocol version: #{client_version}")
            return nil
          end

          # Create DB-backed session
          session = McpSession.create!(
            user: current_user,
            account: current_account,
            protocol_version: negotiated,
            client_info: params["clientInfo"] || {},
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            expires_at: SESSION_TTL.from_now
          )

          # Link OAuth application identity — the auth concern's link_mcp_session_to_application
          # runs before_action but the session doesn't exist yet on initialize requests
          if @doorkeeper_token&.application_id.present?
            session.update_columns(oauth_application_id: @doorkeeper_token.application_id)
          end

          # Resolve and bind MCP client agent identity to the session
          agent = mcp_client_agent
          session.link_agent!(agent) if agent

          protocol_service = build_protocol_service

          response.set_header("Mcp-Session-Id", session.session_token)

          {
            protocolVersion: negotiated,
            capabilities: protocol_service.build_server_capabilities,
            serverInfo: {
              name: "Powernode AI Platform",
              version: Rails.application.config.respond_to?(:version) ? Rails.application.config.version : "1.0.0"
            }
          }
        end

        def handle_tools_list(_params)
          # Combine agent tools from the MCP registry with platform tool definitions.
          # RegistryService is in-memory per instance and only loads agents on init,
          # so platform tools must be merged separately.
          protocol_service = build_protocol_service
          agent_tools = protocol_service.list_tools({}, user: current_user)

          # Build platform tool list in MCP schema format
          platform_tools = ::Ai::Tools::PlatformApiToolRegistry.tool_definitions.map do |defn|
            {
              "name" => "platform.#{defn[:name]}",
              "description" => defn[:description],
              "inputSchema" => build_input_schema(defn[:parameters])
            }
          end

          introspection_tools = ::Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS.map do |defn|
            { "name" => defn[:id], "description" => defn[:description], "inputSchema" => defn[:input_schema] }
          end

          { "tools" => (agent_tools["tools"] || []) + platform_tools + introspection_tools }
        end

        def handle_tools_call(params)
          tool_name = params["name"]
          arguments = params["arguments"] || {}

          unless tool_name.present?
            render_jsonrpc_error(nil, -32602, "Missing required parameter: name")
            return nil
          end

          # Route platform tools: try PlatformApiToolRegistry first, then
          # fall back to Introspection tools (platform.health, platform.metrics, etc.)
          if tool_name.start_with?("platform.")
            begin
              result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
                tool_name,
                params: arguments,
                account: current_account,
                user: current_user,
                mcp_agent: mcp_client_agent
              )
            rescue ArgumentError
              result = ::Ai::Introspection::McpToolRegistrar.execute_tool(
                tool_name,
                params: arguments.symbolize_keys,
                account: current_account
              )
            end
          else
            protocol_service = build_protocol_service
            result = protocol_service.invoke_tool(
              tool_name,
              arguments,
              { user: current_user }
            )
            # ProtocolService wraps in jsonrpc envelope — extract the result
            result = result[:result] if result.is_a?(Hash) && result.key?(:result)
          end

          # Wrap in MCP content format
          response_payload = {
            content: [
              { type: "text", text: result.to_json }
            ]
          }
          response_payload[:isError] = true if result.is_a?(Hash) && result[:success] == false
          response_payload
        end

        def handle_resources_list(params)
          provider = ::Mcp::NativeResourceProvider.new(account: current_account)
          provider.list_resources(cursor: params["cursor"])
        end

        def handle_resources_read(params)
          uri = params["uri"]
          unless uri.present?
            render_jsonrpc_error(nil, -32602, "Missing required parameter: uri")
            return nil
          end

          provider = ::Mcp::NativeResourceProvider.new(account: current_account)
          provider.read_resource(uri: uri)
        end

        def handle_prompts_list(params)
          provider = ::Mcp::NativePromptProvider.new(account: current_account)
          provider.list_prompts(cursor: params["cursor"])
        end

        def handle_prompts_get(params)
          name = params["name"]
          unless name.present?
            render_jsonrpc_error(nil, -32602, "Missing required parameter: name")
            return nil
          end

          provider = ::Mcp::NativePromptProvider.new(account: current_account)
          provider.get_prompt(name: name, arguments: params["arguments"] || {})
        end

        # =====================================================================
        # JSON-RPC Response Helpers
        # =====================================================================

        def render_jsonrpc_result(id, result)
          render json: {
            jsonrpc: "2.0",
            id: id,
            result: result
          }, status: :ok
        end

        def render_jsonrpc_error(id, code, message)
          render json: {
            jsonrpc: "2.0",
            id: id,
            error: {
              code: code,
              message: message
            }
          }, status: :ok
        end

        def build_input_schema(parameters)
          return { "type" => "object", "properties" => {}, "required" => [] } if parameters.blank?

          properties = {}
          required = []

          parameters.each do |name, defn|
            properties[name.to_s] = {
              "type" => defn[:type] || "string",
              "description" => defn[:description]
            }.compact
            required << name.to_s if defn[:required]
          end

          { "type" => "object", "properties" => properties, "required" => required }
        end

        def build_protocol_service
          ::Mcp::ProtocolService.new(
            account: current_account,
            connection_id: request.headers["Mcp-Session-Id"] || SecureRandom.uuid
          )
        end

        def streaming_accepted?
          request.headers["Accept"]&.include?("text/event-stream")
        end

        def handle_streaming_tools_call(params, message_id)
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["Cache-Control"] = "no-cache"
          response.headers["X-Accel-Buffering"] = "no"

          sse = ActionController::Live::SSE.new(response.stream, retry: 5000)

          begin
            result = handle_tools_call(params)

            if performed?
              # handle_tools_call rendered a JSON error (e.g. missing param) — extract and re-emit as SSE
              return
            end

            sse.write({
              jsonrpc: "2.0",
              id: message_id,
              result: result
            }, event: "message")
          rescue ::Mcp::ProtocolService::PermissionDeniedError => e
            sse.write({ jsonrpc: "2.0", id: message_id, error: { code: -32001, message: e.message } }, event: "message")
          rescue ::Mcp::ProtocolService::ToolNotFoundError => e
            sse.write({ jsonrpc: "2.0", id: message_id, error: { code: -32601, message: e.message } }, event: "message")
          rescue ::Mcp::ProtocolService::SchemaValidationError, ArgumentError => e
            sse.write({ jsonrpc: "2.0", id: message_id, error: { code: -32602, message: e.message } }, event: "message")
          rescue StandardError => e
            Rails.logger.error "[MCP StreamableHTTP] Streaming error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
            sse.write({ jsonrpc: "2.0", id: message_id, error: { code: -32603, message: "Internal error: #{e.message}" } }, event: "message")
          ensure
            sse&.close rescue nil
          end
        end

        def find_mcp_session
          session_id = request.headers["Mcp-Session-Id"]
          return nil unless session_id.present?

          McpSession.active.find_by(session_token: session_id)
        end

        def workspace_channels_for_agent(agent)
          ::Ai::Conversation
            .joins(agent_team: :members)
            .where(ai_agent_team_members: { ai_agent_id: agent.id })
            .where(ai_agent_teams: { team_type: "workspace" })
            .pluck(:websocket_channel)
            .compact
        end

        def mcp_client_agent
          @mcp_client_agent ||= begin
            return nil unless @doorkeeper_token

            ::Ai::McpClientIdentityService.new(
              account: current_account,
              user: current_user,
              doorkeeper_token: @doorkeeper_token
            ).resolve_agent
          end
        end

        def current_user
          @current_user
        end

        def current_account
          @current_account
        end

        # --- Session-level SSE dedup helpers ---

        def sse_dedup_for_session(session_token)
          @@sse_dedup_registry_mutex.synchronize do
            # Evict stale entries (older than 1 hour)
            cutoff = 1.hour.ago
            @@sse_dedup_registry.delete_if { |_, v| v[:last_access] < cutoff }

            @@sse_dedup_registry[session_token] ||= {
              mutex: Mutex.new,
              ids: Set.new,
              last_access: Time.current
            }
          end
        end

        # Returns true if msg_id was already seen (duplicate), false if first time.
        def sse_dedup_seen?(dedup, msg_id)
          dedup[:mutex].synchronize do
            dedup[:last_access] = Time.current
            if dedup[:ids].include?(msg_id)
              true
            else
              dedup[:ids] << msg_id
              dedup[:ids].delete(dedup[:ids].first) if dedup[:ids].size > 200
              false
            end
          end
        end
      end
    end
  end
end

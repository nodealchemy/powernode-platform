# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class StreamableHttpController < ApplicationController
        include ActionController::Live
        include McpTokenAuthentication

        MCP_PROTOCOL_VERSION = "2025-11-25"
        SESSION_TTL = 24.hours
        SSE_KEEPALIVE_INTERVAL = 30 # seconds between SSE pings (keeps connection alive)
        SSE_ACTIVITY_TOUCH_CYCLES = 10 # Touch DB every N keepalive cycles (~5 min) — not every ping
        SSE_CHANNEL_REFRESH_CYCLES = 12 # Re-check workspace channels every N keepalive cycles (~6 min)
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
            is_workspace = workspace_channel_set.include?(channel)
            callback = is_workspace ? build_workspace_callback(channel, sse, agent, dedup) : build_session_callback(sse)
            callbacks[channel] = callback
            pubsub.subscribe(channel, callback)
          end

          # Release the DB connection back to the pool before entering the
          # long-lived keepalive loop. SSE streams tie up a Puma thread for
          # hours/days — if they also hold a DB connection, the pool is exhausted
          # and all normal HTTP requests block until ConnectionTimeoutError.
          ActiveRecord::Base.connection_handler.clear_active_connections!

          # Keepalive loop — sends SSE pings every 30s to keep the connection alive,
          # but only touches the DB periodically (every ~5 min) to avoid saturating
          # the connection pool when many SSE sessions are active.
          keepalive_cycle = 0
          loop do
            sleep SSE_KEEPALIVE_INTERVAL
            sse.write({ type: "ping", timestamp: Time.current.iso8601 }, event: "ping")
            keepalive_cycle += 1

            # DB operations: only on specific cycles to reduce connection pool pressure
            needs_touch = (keepalive_cycle % SSE_ACTIVITY_TOUCH_CYCLES).zero?
            needs_channel_refresh = agent && (keepalive_cycle % SSE_CHANNEL_REFRESH_CYCLES).zero?

            next unless needs_touch || needs_channel_refresh

            ActiveRecord::Base.connection_pool.with_connection do
              session.touch_activity! if needs_touch

              # Periodically re-check workspace channels and subscribe to new ones.
              # Handles the race where an agent is added to a workspace AFTER the
              # SSE stream connects (e.g., MCP client agents that are invited
              # asynchronously after session initialization).
              if needs_channel_refresh
                fresh_channels = workspace_channels_for_agent(agent)
                new_channels = fresh_channels.reject { |ch| workspace_channel_set.include?(ch) }
                new_channels.each do |channel|
                  workspace_channel_set << channel
                  callback = build_workspace_callback(channel, sse, agent, dedup)
                  callbacks[channel] = callback
                  pubsub.subscribe(channel, callback)
                  Rails.logger.info "[MCP StreamableHTTP] Late-subscribed to workspace channel: #{channel} (agent: #{agent.name})"
                end
              end
            end
          end
        rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
          # Client disconnected — revoke session to trigger agent archival.
          # Must borrow a connection since we released ours before the loop.
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              session&.revoke! if session&.active?
            end
          rescue StandardError => e
            Rails.logger.warn "[MCP StreamableHTTP] Session revoke on disconnect failed: #{e.message}"
          end
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

          if session_id.present?
            session = McpSession.find_by(session_token: session_id, status: "active")

            # Reconnect recovery: if the session was recently revoked (e.g., server
            # restart dropped the SSE connection), reactivate it. The OAuth token is
            # already validated by authenticate_mcp_request, so the client is legit.
            if session.nil?
              revoked_session = McpSession.find_by(session_token: session_id)
              if revoked_session&.reactivatable?
                revoked_session.reactivate!
                session = revoked_session
              end
            end
          end

          # Fallback: find any active session for this user/account/app.
          # Handles requests without Mcp-Session-Id (e.g., first request after
          # auto-provision) or with an expired/revoked session ID.
          if session.nil? && @doorkeeper_token&.application_id.present?
            session = McpSession.active
              .where(user: current_user, account: current_account,
                     oauth_application_id: @doorkeeper_token.application_id)
              .order(created_at: :desc)
              .first
          end

          return unless session

          # Store for mcp_client_agent fallback — it prefers Mcp-Session-Id header
          # but falls back to this when the header is missing or stale.
          @tracked_session = session

          # Deferred agent linking: if session has no agent but one is resolvable now, link it.
          # Runs on ALL request methods (including GET/SSE) to catch sessions that were
          # created before identity resolution was deployed.
          resolve_and_link_agent(session) if session.ai_agent_id.nil?

          # SSE stream connections (GET) are passive listeners — they should NOT
          # refresh last_activity_at. Only actual JSON-RPC requests (POST) count
          # as real CLI activity. This ensures that when a CLI disconnects, its
          # session's last_activity_at goes stale even if the SSE daemon stays
          # connected, allowing expire_previous_sessions! to clean it up.
          return if request.get?

          session.touch_activity!
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
          when "session/discover"
            handle_session_discover(params)
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

          # Reuse auto-provisioned sessions (created by session/discover self-healing)
          # instead of creating a new session + agent. This prevents the race where
          # session/discover auto-provisions agent #1, then initialize creates agent #2.
          session = nil
          if @doorkeeper_token&.application_id.present?
            auto_session = McpSession.active
              .where(user: current_user, account: current_account,
                     oauth_application_id: @doorkeeper_token.application_id)
              .where("client_info->>'version' = ?", "auto-provisioned")
              .order(created_at: :desc)
              .first

            if auto_session
              auto_session.update!(
                protocol_version: negotiated,
                client_info: params["clientInfo"] || {},
                ip_address: request.remote_ip,
                user_agent: request.user_agent,
                expires_at: SESSION_TTL.from_now
              )
              session = auto_session
              Rails.logger.info "[MCP StreamableHTTP] Upgraded auto-provisioned session #{session.id} with real client info"
            end
          end

          unless session
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
          end

          # Resolve and bind MCP client agent identity to the session.
          # The block runs inside the advisory lock transaction so link_agent!
          # commits atomically with agent creation — preventing another concurrent
          # request from seeing the agent as orphaned between creation and binding.
          # Skip if the upgraded auto-provisioned session already has an agent linked.
          agent = resolve_and_link_agent(session) unless session.ai_agent_id.present?

          # Allow multiple concurrent sessions per OAuth app (e.g., multiple Claude
          # Code instances). Stale sessions expire naturally via their 24h TTL and the
          # daily cleanup job (McpSession.cleanup_expired!).
          # session.expire_previous_sessions!

          protocol_service = build_protocol_service

          response.set_header("Mcp-Session-Id", session.session_token)
          response.set_header("X-Mcp-Display-Name", session.display_name || session.ai_agent&.name || "MCP")

          {
            protocolVersion: negotiated,
            capabilities: protocol_service.build_server_capabilities,
            serverInfo: {
              name: "Powernode AI Platform",
              version: Rails.application.config.respond_to?(:version) ? Rails.application.config.version : "1.0.0"
            }
          }
        end

        def handle_session_discover(_params)
          # Include grace-period sessions so daemons can reclaim their own session
          # after disconnect. The server will call reactivate! automatically when
          # the daemon sends an SSE GET with the revoked session token.
          scope = McpSession.active.or(McpSession.in_grace_period)
            .where(user: current_user, account: current_account)

          if @doorkeeper_token&.application_id.present?
            scope = scope.where(oauth_application_id: @doorkeeper_token.application_id)
          end

          discovered = scope.order(created_at: :desc).limit(10).includes(:ai_agent).to_a

          # Self-healing: no sessions survived for this authenticated client.
          # Auto-provision one so the SSE daemon (and workspace UI) can recover
          # from the dead state caused by server restarts or cleanup tasks.
          if discovered.empty? && @doorkeeper_token&.application_id.present?
            new_session = auto_provision_mcp_session
            discovered = [new_session] if new_session
          end

          sessions = discovered.map do |s|
            {
              session_token: s.session_token,
              display_name: s.display_name || s.ai_agent&.name,
              agent_id: s.ai_agent_id,
              created_at: s.created_at.iso8601,
              last_activity_at: s.last_activity_at&.iso8601,
              client_info: s.client_info,
              status: s.status
            }
          end

          { sessions: sessions }
        end

        def handle_tools_list(_params)
          # Only expose platform and introspection tools in tools/list.
          # Agent tools (one per AI agent) are excluded from listing to avoid
          # flooding MCP clients with thousands of entries. Agents remain
          # callable via tools/call and discoverable via platform.list_agents
          # + platform.execute_agent.
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

          { "tools" => platform_tools + introspection_tools }
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
            rescue ArgumentError => e
              if e.message.start_with?("Unknown platform tool")
                result = ::Ai::Introspection::McpToolRegistrar.execute_tool(
                  tool_name,
                  params: arguments.symbolize_keys,
                  account: current_account
                )
              else
                result = { success: false, error: e.message }
              end
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

          # Already in JSON Schema format (has type + properties keys)
          if parameters.is_a?(Hash) && (parameters[:type] == "object" || parameters["type"] == "object")
            props = parameters[:properties] || parameters["properties"] || {}
            return {
              "type" => "object",
              "properties" => props.transform_keys(&:to_s).transform_values { |v|
                v.is_a?(Hash) ? v.transform_keys(&:to_s) : { "type" => v.to_s }
              },
              "required" => (parameters[:required] || parameters["required"] || []).map(&:to_s)
            }
          end

          # Flat hash format: { name: { type:, description:, required: } }
          properties = {}
          required = []

          parameters.each do |name, defn|
            next unless defn.is_a?(Hash)

            properties[name.to_s] = {
              "type" => defn[:type]&.to_s || defn["type"]&.to_s || "string",
              "description" => defn[:description] || defn["description"]
            }.compact
            required << name.to_s if defn[:required] || defn["required"]
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

          session = McpSession.active.find_by(session_token: session_id)
          return session if session

          # Reconnect recovery for SSE streams (e.g., daemon reconnecting after server restart)
          revoked_session = McpSession.find_by(session_token: session_id)
          if revoked_session&.reactivatable?
            revoked_session.reactivate!
            revoked_session
          end
        end

        def workspace_channels_for_agent(agent)
          ::Ai::Conversation
            .joins(agent_team: :members)
            .where(ai_agent_team_members: { ai_agent_id: agent.id })
            .where(ai_agent_teams: { team_type: "workspace" })
            .pluck(:websocket_channel)
            .compact
        end

        # Self-healing session creation for the dead state where all sessions
        # expired beyond grace period and agents were destroyed. Called from
        # handle_session_discover when no sessions exist for an authenticated client.
        # Creates a new session + agent so the SSE daemon can discover and claim it.
        def auto_provision_mcp_session
          app_id = @doorkeeper_token.application_id

          # Guard: don't create if a concurrent request just created one
          existing = McpSession.active
            .where(user: current_user, account: current_account, oauth_application_id: app_id)
            .first
          return existing if existing

          app_name = @doorkeeper_token.application&.name || "MCP Client"

          session = McpSession.create!(
            user: current_user,
            account: current_account,
            protocol_version: MCP_PROTOCOL_VERSION,
            client_info: { "name" => app_name, "version" => "auto-provisioned" },
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            expires_at: SESSION_TTL.from_now,
            oauth_application_id: app_id
          )

          resolve_and_link_agent(session)

          Rails.logger.info(
            "[MCP StreamableHTTP] Auto-provisioned session #{session.id} " \
            "with agent #{session.reload.display_name} (#{session.ai_agent_id}) — self-heal recovery"
          )
          session
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.warn "[MCP StreamableHTTP] Auto-provision failed: #{e.message}"
          nil
        end

        # Resolves the MCP client agent and links it to the session inside the
        # same advisory-locked transaction, ensuring atomicity.
        def resolve_and_link_agent(session)
          return nil unless @doorkeeper_token

          ::Ai::McpClientIdentityService.new(
            account: current_account,
            user: current_user,
            doorkeeper_token: @doorkeeper_token
          ).resolve_agent do |agent|
            session.link_agent!(agent)
          end
        end

        def mcp_client_agent
          @mcp_client_agent ||= begin
            return nil unless @doorkeeper_token

            # Prefer the agent already bound to the current MCP session (from
            # Mcp-Session-Id header), falling back to the session resolved by
            # track_session_activity (OAuth app fallback). This avoids creating
            # transient agents on every tools/call when a valid session exists.
            session_agent = (current_mcp_session || @tracked_session)&.ai_agent
            if session_agent&.active? && session_agent&.mcp_client?
              session_agent
            else
              ::Ai::McpClientIdentityService.new(
                account: current_account,
                user: current_user,
                doorkeeper_token: @doorkeeper_token
              ).resolve_agent
            end
          end
        end

        def current_mcp_session
          @current_mcp_session ||= begin
            session_id = request.headers["Mcp-Session-Id"]
            return nil unless session_id.present?

            McpSession.find_by(session_token: session_id, status: "active")
          end
        end

        def current_user
          @current_user
        end

        def current_account
          @current_account
        end

        # --- SSE callback builders ---

        # Builds a callback for the MCP session channel (JSON-RPC notifications only)
        def build_session_callback(sse)
          proc do |raw_message|
            data = JSON.parse(raw_message) rescue next
            if data["jsonrpc"] == "2.0" && data["method"].is_a?(String)
              sse.write(data, event: "message")
            end
          end
        end

        # Builds a callback for workspace channels (filters by agent type and mention)
        def build_workspace_callback(_channel, sse, agent, dedup)
          proc do |raw_message|
            data = JSON.parse(raw_message) rescue next

            event_type = data["type"] || data[:type]
            next unless ALLOWED_WORKSPACE_EVENTS.include?(event_type.to_s)

            # MCP client agents receive ALL workspace events (filtered client-side by daemon).
            # Non-MCP agents only receive events where they are @mentioned.
            # Structural events (agent_joined/agent_left) pass through unfiltered.
            if %w[message_created ai_response_complete].include?(event_type.to_s)
              unless agent&.agent_type == "mcp_client"
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

                unless agent_mentioned
                  content = (msg["content"] || "").to_s
                  agent_mentioned = agent&.name.present? && content.include?("@#{agent.name}")
                end

                next unless agent_mentioned
              end
            end

            # Deduplicate across channels and concurrent SSE connections
            msg_id = (data["message"].is_a?(Hash) && data["message"]["id"]) || data["message_id"]
            if msg_id.present?
              dedup_key = "#{event_type}:#{msg_id}"
              next if sse_dedup_seen?(dedup, dedup_key)
            end

            sse.write(data, event: event_type.to_s)
          end
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

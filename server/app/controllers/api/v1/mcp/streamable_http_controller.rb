# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class StreamableHttpController < ApplicationController
        include ActionController::Live
        include McpTokenAuthentication

        # controller-size-exempt: ActionController::Live streaming MCP endpoint. The SSE
        # stream lifecycle (response.stream writes across threads + the dedup mutex) is
        # irreducibly controller-bound and cannot be lifted into a service to reach the
        # 300-line target. The JSON-RPC dispatch and session-provisioning helpers MAY be
        # extracted to services as a future refinement (ref IMP-fe2c4e9fcb00); the
        # residual streaming glue keeps this controller above the limit by design.

        # Default response-header version for the stateful (handshake) era.
        # Stateless-era requests (2026-07-28) get their own version echoed —
        # see validate_stateless_transport!.
        MCP_PROTOCOL_VERSION = "2025-11-25"
        SESSION_TTL = 24.hours

        # tools/list page size. Must stay AHEAD of the advertised catalog so a
        # client that never sends a cursor still receives the complete set in
        # one page with no nextCursor.
        #
        # Deliberately NOT documented here as "larger than the current N tools".
        # It was, and that is exactly how this broke: the bound was set to 250
        # when the catalog held 231, the catalog grew to 611 (602 platform + 9
        # introspection), and pagination engaged silently. Uncursored clients
        # received 250 tools and lost 361 — a well-formed response, no error,
        # no warning, and tools that are implemented, registered and
        # relevance-filtered simply never offered. A comment cannot hold an
        # invariant, so the invariant is executed instead:
        # spec/requests/api/v1/mcp/tools_list_page_size_spec.rb fails when the
        # catalog reaches 90% of this bound, naming both numbers.
        #
        # Raise this when that spec warns. Lowering it is only safe once every
        # client follows nextCursor — the truncation it causes is invisible.
        TOOLS_PAGE_SIZE = 1000

        # Methods whose Mcp-Name request header must mirror params.name /
        # params.uri (2026-07-28 Streamable HTTP request metadata).
        NAME_HEADER_METHODS = %w[tools/call resources/read prompts/get].freeze


        # CacheableResult hints for stateless-era (2026-07-28) responses.
        # All catalogs are principal/account-scoped → cacheScope "private".
        LIST_RESULT_TTL_MS = 300_000 # 5 min freshness hint for list endpoints
        READ_RESULT_TTL_MS = 0       # resource contents: always re-fetch
        DISCOVER_TTL_MS = 3_600_000  # server identity/capabilities: 1 h
        CACHEABLE_METHOD_TTLS = {
          "tools/list" => LIST_RESULT_TTL_MS,
          "prompts/list" => LIST_RESULT_TTL_MS,
          "resources/list" => LIST_RESULT_TTL_MS,
          "resources/templates/list" => LIST_RESULT_TTL_MS,
          "resources/read" => READ_RESULT_TTL_MS
        }.freeze

        # Conservative read-only heuristic for ToolAnnotations.readOnlyHint
        # (2025-03-26+). Annotations are untrusted hints per spec; only tools
        # whose action name is unambiguously read-only get the hint.
        READ_ONLY_ACTION_PREFIXES = %w[list get search query read describe check discover perceive measure recent].freeze
        READ_ONLY_ACTION_NAMES = %w[health metrics resources scoreboard].freeze
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

          # Remember the request id so nested handler error renders carry it
          # (JSON-RPC 2.0 requires error responses to echo the request id).
          @jsonrpc_id = message_id

          # 2026-07-28 stateless-era transport validation (per-request _meta
          # protocol version, Mcp-Method / Mcp-Name header mirroring).
          validate_stateless_transport!(body)
          return if performed?

          # Stream tools/call responses as SSE when client accepts it
          if streaming_accepted? && method == "tools/call"
            handle_streaming_tools_call(params, message_id)
            return
          end

          result = dispatch_method(method, params, message_id)
          return if performed?

          result = apply_stateless_result_envelope(method, result) if stateless_request?
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
            session = McpSession.find_by(session_token: session_id)
            session.revoke! if session_owned_by_current_principal?(session)
          end

          head :ok
        end

        # GET /api/v1/mcp/message
        # Opens an SSE stream for push notifications (MCP notifications + workspace events)
        # Agent identity is optional — sessions without agents receive MCP notifications only
        def stream
          session = find_mcp_session
          unless session
            render json: { error: "Session not found or expired", error_code: "session_invalid" }, status: :bad_request
            return
          end

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

        # Methods a RESTRICTED principal (instance / federation) may use. Default-
        # deny: a restricted caller is scoped to a TOOL allowlist, so it gets the
        # handshake + tools/* only — never resources/*, prompts/*, completion/*,
        # or the session/server DISCOVERY methods. Excluding session/discover is
        # deliberate: a restricted principal (user:nil) has no legitimate
        # cross-session reclaim need, and session/discover keys on user:nil, which
        # would otherwise enumerate every other null-user principal's session
        # tokens in the account. This is the single dispatch-level gate on every
        # door rather than per-handler.
        RESTRICTED_PRINCIPAL_METHODS = %w[
          initialize ping tools/list tools/call
        ].freeze

        def dispatch_method(method, params, message_id)
          if current_mcp_principal&.restricted? && !RESTRICTED_PRINCIPAL_METHODS.include?(method)
            render_jsonrpc_error(message_id, -32601,
                                 "Method not available to this principal: #{method}",
                                 status: stateless_request? ? :not_found : :ok)
            return nil
          end

          case method
          when "initialize"
            handle_initialize(params, message_id)
          when "server/discover"
            handle_server_discover(params)
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
          when "resources/templates/list"
            handle_resources_templates_list(params)
          when "resources/read"
            handle_resources_read(params)
          when "prompts/list"
            handle_prompts_list(params)
          when "prompts/get"
            handle_prompts_get(params)
          when "completion/complete"
            handle_completion_complete(params)
          else
            # 2026-07-28 requires HTTP 404 for unknown RPC methods; the
            # stateful era keeps the historical 200 + JSON-RPC error.
            render_jsonrpc_error(message_id, -32601, "Method not found: #{method}",
                                 status: stateless_request? ? :not_found : :ok)
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

          # Reuse an existing session for this OAuth app instead of creating a new one.
          # Priority: (1) auto-provisioned sessions (placeholders from session/discover),
          # (2) stale active sessions (SSE disconnected, daemon dead — last activity > 60s).
          # This prevents agent identity accumulation on reconnects.
          session = nil
          if @doorkeeper_token&.application_id.present?
            reusable_session = McpSession.active
              .where(user: current_user, account: current_account,
                     oauth_application_id: @doorkeeper_token.application_id)
              .where(
                "client_info->>'version' = ? OR last_activity_at < ?",
                "auto-provisioned", 60.seconds.ago
              )
              .order(Arel.sql("CASE WHEN client_info->>'version' = 'auto-provisioned' THEN 0 ELSE 1 END, created_at DESC"))
              .first

            if reusable_session
              reusable_session.update!(
                protocol_version: negotiated,
                client_info: params["clientInfo"] || {},
                ip_address: request.remote_ip,
                user_agent: request.user_agent,
                expires_at: SESSION_TTL.from_now
              )
              session = reusable_session
              Rails.logger.info "[MCP StreamableHTTP] Reused session #{session.id} (was #{session.client_info_before_last_save&.dig('version') == 'auto-provisioned' ? 'auto-provisioned' : 'stale'}) with real client info"
            end
          end

          unless session
            # Create DB-backed session
            session = McpSession.create!(
              **session_principal_attributes,
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
          agent = resolve_and_link_agent(session, client_info: params["clientInfo"] || {}) unless session.ai_agent_id.present?

          # Allow multiple concurrent sessions per OAuth app (e.g., multiple Claude
          # Code instances). Stale sessions expire naturally via their 24h TTL and the
          # daily cleanup job (McpSession.cleanup_expired!).
          # session.expire_previous_sessions!

          protocol_service = build_protocol_service

          response.set_header("Mcp-Session-Id", session.session_token)
          response.set_header("X-Mcp-Display-Name", session.display_name || session.ai_agent&.name || "MCP")

          {
            protocolVersion: negotiated,
            capabilities: protocol_service.build_server_capabilities(protocol_version: negotiated),
            serverInfo: {
              name: "Powernode AI Platform",
              version: Rails.application.config.respond_to?(:version) ? Rails.application.config.version : "1.0.0"
            }
          }
        end

        def handle_session_discover(params)
          # Restricted principals (instance/federation, user:nil) have no
          # cross-session reclaim need and are already excluded from this method
          # by the dispatch allowlist; this is the defense-in-depth backstop so a
          # user:nil principal can never enumerate other principals' sessions.
          return { sessions: [] } if current_mcp_principal&.restricted?

          client_instance_id = params["client_instance_id"]

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
            new_session = auto_provision_mcp_session(client_instance_id: client_instance_id)
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
              client_instance_id: s.metadata&.dig("client_instance_id"),
              status: s.status
            }
          end

          { sessions: sessions }
        end

        def handle_tools_list(params)
          # Cursor pagination (opaque offset cursor). Invalid cursors are a
          # protocol error per spec (-32602).
          cursor = params["cursor"]
          offset = 0
          if cursor.present?
            unless cursor.to_s.match?(/\A\d+\z/)
              render_jsonrpc_error(nil, -32602, "Invalid cursor: #{cursor}")
              return nil
            end
            offset = cursor.to_i
          end

          # Only expose platform and introspection tools in tools/list.
          # Agent tools (one per AI agent) are excluded from listing to avoid
          # flooding MCP clients with thousands of entries. Agents remain
          # callable via tools/call and discoverable via platform.list_agents
          # + platform.execute_agent.
          platform_tools = ::Ai::Tools::PlatformApiToolRegistry.tool_definitions.map do |defn|
            decorate_tool_entry(
              "name" => "platform.#{defn[:name]}",
              "description" => defn[:description],
              "inputSchema" => build_input_schema(defn[:parameters])
            )
          end

          introspection_tools = ::Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS.map do |defn|
            decorate_tool_entry(
              "name" => defn[:id],
              "description" => defn[:description],
              "inputSchema" => defn[:input_schema]
            )
          end

          all_tools = platform_tools + introspection_tools
          # Instance principals get a default-deny, grant-scoped catalog; users keep
          # the full list (their per-tool permissions gate execution).
          tools = current_mcp_principal ? current_mcp_principal.filter_tools(all_tools) : all_tools

          # Deterministic order (2026-07-28 SHOULD) — also keeps pagination
          # cursors stable across processes and deploys.
          tools = tools.sort_by { |tool| tool["name"].to_s }

          page = tools.slice(offset, TOOLS_PAGE_SIZE) || []
          result = { "tools" => page }
          result["nextCursor"] = (offset + TOOLS_PAGE_SIZE).to_s if tools.size > offset + TOOLS_PAGE_SIZE
          result
        end

        def handle_tools_call(params)
          tool_name = params["name"]
          arguments = params["arguments"] || {}

          unless tool_name.present?
            render_jsonrpc_error(nil, -32602, "Missing required parameter: name")
            return nil
          end

          # Restricted principals (instance / federation) are default-deny: gate
          # execution against their grant (instance grant glob, or a federation
          # partner's allowed_capabilities), and never a destroy-shaped tool. This
          # is the authorization gate that prevents a user:nil principal from
          # reaching the internal-caller permission bypass below. (Users fall
          # through; their per-tool permission check still applies in the registrar.)
          if current_mcp_principal&.restricted? && !current_mcp_principal.may_invoke?(tool_name)
            render_jsonrpc_error(nil, -32000, "Tool not permitted for this principal: #{tool_name}")
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
                mcp_agent: mcp_client_agent,
                # Restricted principals (instance / federation) are already
                # grant-gated above; let the registrar skip the user-permission
                # check for them, hold the action to that same granted name, and
                # re-arm the destroy-shaped deny overlay at every nested hop. The
                # flag is named for its first use but is mechanically generic —
                # BaseTool#enforce_instance_deny_overlay! keys on it, not on a
                # node_instance (which federation has none of). (BUG-R)
                instance_authorized: current_mcp_principal&.restricted? || false,
                # ...and give the tool the instance so DevLoopTool#claimant_ref can
                # scope claims as "instance:<id>" (nil for user/agent). (BUG-S)
                node_instance: current_mcp_principal&.node_instance
              )
            rescue ArgumentError => e
              if e.message.start_with?("Unknown platform tool")
                # Thread the principal through. Passing only `account:` left
                # ai.introspection.view unenforceable AND the registrar's
                # per-agent rate limiter dead, since both need context this
                # call was discarding. instance_authorized mirrors the sibling
                # branch above: a restricted principal is already gated against
                # the granted tool name at tools/call and holds no User.
                result = ::Ai::Introspection::McpToolRegistrar.execute_tool(
                  tool_name,
                  params: arguments.symbolize_keys,
                  account: current_account,
                  user: current_user,
                  # restricted?, matching the sibling branch at the top of this
                  # same rescue. instance? left FEDERATION principals denied:
                  # one whose allowed_capabilities include platform.health
                  # passes may_invoke? above, lands here with instance_authorized
                  # false and user nil (federation principals carry no User), and
                  # is refused by a gate that had already authorized it.
                  instance_authorized: current_mcp_principal&.restricted? || false,
                  agent_id: mcp_client_agent&.id
                )
              else
                result = { success: false, error: e.message }
              end
            rescue ::Ai::Introspection::RateLimiter::RateLimitExceeded => e
              # Threading agent_id above re-armed this limiter, which had been
              # dead on this path because the call discarded the agent. Its
              # RateLimitExceeded is a StandardError, not an ArgumentError, so
              # without this clause it escaped to the controller's generic
              # handler and surfaced as a JSON-RPC -32603 "internal error" with
              # retry_after discarded — an unretryable-looking failure for a
              # condition that is purely retryable. Shaped like the sibling
              # error result below, and like Ai::AgentToolBridgeService's
              # existing handling of the same exception.
              result = { success: false, error: e.message,
                         rate_limited: true, retry_after: e.retry_after }
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
          # Structured tool output (2025-06-18+). The advertised outputSchema is
          # { "type" => "object" }, so structuredContent must always be a JSON
          # object — non-object results are wrapped under "result". Never sent
          # to clients on 2025-03-26 / 2024-11-05, which predate the field.
          if protocol_at_least?("2025-06-18")
            response_payload[:structuredContent] = result.is_a?(Hash) ? result : { "result" => result }
          end
          response_payload[:isError] = true if result.is_a?(Hash) && result[:success] == false
          response_payload
        end

        def handle_resources_templates_list(params)
          provider = ::Mcp::NativeResourceProvider.new(account: current_account)
          provider.list_resource_templates(cursor: params["cursor"])
        end

        # server/discover (2026-07-28): mandatory version/capability probe.
        # Answered for every client era — it is explicitly the request a
        # client MAY use to find out which revisions this server speaks, so
        # the CacheableResult fields required by its schema are always
        # included rather than being version-gated.
        def handle_server_discover(_params)
          {
            "supportedVersions" => ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS,
            "capabilities" => build_protocol_service.build_server_capabilities(
              protocol_version: ::Mcp::ProtocolService::STATELESS_VERSIONS.first
            ),
            "instructions" => "Powernode AI Platform control plane. The tool catalog is " \
                              "permission-scoped per authenticated principal; call tools/list for it.",
            "resultType" => "complete",
            "ttlMs" => DISCOVER_TTL_MS,
            "cacheScope" => "public",
            "_meta" => { "io.modelcontextprotocol/serverInfo" => server_info_payload }
          }
        end

        def handle_completion_complete(params)
          ref = params["ref"] || {}
          argument = params["argument"] || {}
          value = argument["value"].to_s

          values =
            case ref["type"]
            when "ref/prompt"
              ::Mcp::NativePromptProvider.new(account: current_account).complete_argument(
                name: ref["name"].to_s,
                argument_name: argument["name"].to_s,
                value: value
              )
            when "ref/resource"
              ::Mcp::NativeResourceProvider.new(account: current_account).complete_uri_template(
                uri_template: ref["uri"].to_s,
                value: value
              )
            else
              render_jsonrpc_error(nil, -32602, "Invalid completion ref type: #{ref['type'].inspect}")
              return nil
            end

          capped = values.first(100)
          completion = { "values" => capped, "hasMore" => values.size > capped.size }
          # total is optional and must be accurate; providers fetch at most
          # one page + 1, so it is only known when nothing was truncated.
          completion["total"] = values.size unless completion["hasMore"]
          { "completion" => completion }
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

        # JSON-RPC 2.0 requires error responses to echo the request id, so
        # handlers that render an error without one fall back to the id
        # captured at dispatch time. `status` defaults to 200 (stateful-era
        # behavior); 2026-07-28 transport errors pass 400/404 explicitly.
        def render_jsonrpc_error(id, code, message, status: :ok, data: nil)
          error = { code: code, message: message }
          error[:data] = data unless data.nil?

          render json: {
            jsonrpc: "2.0",
            id: id.nil? ? @jsonrpc_id : id,
            error: error
          }, status: status
        end

        # ==================================================================
        # Protocol-revision helpers (stateful 2024-11-05..2025-11-25 vs
        # stateless 2026-07-28 on the same endpoint)
        # ==================================================================

        # The protocol revision governing THIS request's response shape.
        # Resolution order: validated per-request _meta / header for the
        # stateless era (set by validate_stateless_transport!), then the
        # MCP-Protocol-Version header, then the session's negotiated version,
        # then 2025-03-26 — the spec-mandated assumption for requests without
        # the header (clients older than 2025-06-18 never sent one).
        def request_protocol_version
          @request_protocol_version ||= begin
            header = request.headers["MCP-Protocol-Version"]
            session = current_mcp_session || @tracked_session

            if ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.include?(header)
              header
            elsif session && ::Mcp::ProtocolService::SUPPORTED_VERSIONS.include?(session.protocol_version)
              session.protocol_version
            else
              "2025-03-26"
            end
          end
        end

        # Protocol revisions are ISO dates, so string comparison orders them.
        def protocol_at_least?(version)
          request_protocol_version >= version
        end

        def stateless_request?
          ::Mcp::ProtocolService::STATELESS_VERSIONS.include?(request_protocol_version)
        end

        # 2026-07-28 Streamable HTTP request validation. Engages only when the
        # request signals the stateless era (a protocolVersion in params._meta
        # or a stateless MCP-Protocol-Version header); every stateful-era
        # request passes through untouched, keeping legacy behavior identical.
        def validate_stateless_transport!(body)
          params = body["params"]
          meta = params.is_a?(Hash) ? params["_meta"] : nil
          meta_version = meta.is_a?(Hash) ? meta["io.modelcontextprotocol/protocolVersion"] : nil
          header = request.headers["MCP-Protocol-Version"]

          return unless meta_version.present? || ::Mcp::ProtocolService::STATELESS_VERSIONS.include?(header)

          requested = meta_version.presence || header

          unless ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.include?(requested)
            render_jsonrpc_error(
              body["id"], -32022, "Unsupported protocol version: #{requested}",
              status: :bad_request,
              data: { supported: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS, requested: requested.to_s }
            )
            return
          end

          # A stateful version carried in _meta is out-of-spec but tolerated;
          # the stateless transport rules below apply only to 2026-07-28+.
          return unless ::Mcp::ProtocolService::STATELESS_VERSIONS.include?(requested)

          # The MCP-Protocol-Version header MUST match _meta's protocolVersion.
          if header != meta_version
            render_jsonrpc_error(
              body["id"], -32020,
              "Header mismatch: MCP-Protocol-Version header #{header.inspect} does not match " \
              "_meta io.modelcontextprotocol/protocolVersion #{meta_version.inspect}",
              status: :bad_request
            )
            return
          end

          # Mcp-Method is required on every request and MUST mirror the body.
          mcp_method = request.headers["Mcp-Method"]
          if mcp_method.to_s != body["method"]
            render_jsonrpc_error(
              body["id"], -32020,
              "Header mismatch: Mcp-Method header #{mcp_method.inspect} does not match body method #{body['method'].inspect}",
              status: :bad_request
            )
            return
          end

          # Mcp-Name MUST mirror params.name / params.uri for named methods.
          if NAME_HEADER_METHODS.include?(body["method"])
            expected = params.is_a?(Hash) ? (params["name"] || params["uri"]).to_s : ""
            provided = decode_mcp_header_value(request.headers["Mcp-Name"])
            if provided.nil? || provided != expected
              render_jsonrpc_error(
                body["id"], -32020,
                "Header mismatch: Mcp-Name header does not match body value #{expected.inspect}",
                status: :bad_request
              )
              return
            end
          end

          @request_protocol_version = requested
          response.set_header("MCP-Protocol-Version", requested)
        end

        # Decodes the Base64 sentinel format (=?base64?...?=) used when a
        # header value cannot be carried as plain ASCII.
        def decode_mcp_header_value(value)
          return nil if value.nil?

          if value.start_with?("=?base64?") && value.end_with?("?=")
            encoded = value.delete_prefix("=?base64?").delete_suffix("?=")
            Base64.decode64(encoded).force_encoding(Encoding::UTF_8)
          else
            value
          end
        end

        # Stateless-era (2026-07-28) result envelope: required resultType,
        # CacheableResult fields on the read/list methods whose schemas
        # require them, and the SHOULD-level serverInfo in result _meta.
        # Never applied to stateful-era responses.
        def apply_stateless_result_envelope(method, result)
          return result unless result.is_a?(Hash)

          enveloped = result.dup
          unless enveloped.key?("resultType") || enveloped.key?(:resultType)
            enveloped["resultType"] = "complete"
          end

          ttl = CACHEABLE_METHOD_TTLS[method]
          if ttl && !enveloped.key?("ttlMs") && !enveloped.key?(:ttlMs)
            enveloped["ttlMs"] = ttl
            enveloped["cacheScope"] = "private"
          end

          existing_meta = enveloped["_meta"] || enveloped[:_meta]
          meta = existing_meta.is_a?(Hash) ? existing_meta.dup : {}
          meta["io.modelcontextprotocol/serverInfo"] ||= server_info_payload
          enveloped.delete(:_meta)
          enveloped["_meta"] = meta
          enveloped
        end

        def server_info_payload
          {
            "name" => "Powernode AI Platform",
            "version" => Rails.application.config.respond_to?(:version) ? Rails.application.config.version : "1.0.0"
          }
        end

        # Version-gated tool metadata for tools/list entries. Fields never
        # leak to revisions that predate them: annotations (2025-03-26),
        # title + outputSchema (2025-06-18).
        def decorate_tool_entry(tool)
          action = tool["name"].to_s.delete_prefix("platform.")

          if protocol_at_least?("2025-03-26") && read_only_action?(action)
            tool["annotations"] = { "readOnlyHint" => true }
          end

          if protocol_at_least?("2025-06-18")
            tool["title"] = action.split("_").map(&:capitalize).join(" ")
            # The generic object schema is the truthful contract: every
            # tools/call result serializes a JSON object into
            # structuredContent (see handle_tools_call).
            tool["outputSchema"] = { "type" => "object" }
          end

          tool
        end

        def read_only_action?(action)
          READ_ONLY_ACTION_NAMES.include?(action) ||
            READ_ONLY_ACTION_PREFIXES.include?(action.split("_").first)
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

            result = apply_stateless_result_envelope("tools/call", result) if stateless_request?

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
          # A session is only visible to the principal that owns it, in its own
          # account — a token alone must not grant another principal the stream.
          if session
            return session_owned_by_current_principal?(session) ? session : nil
          end

          # Reconnect recovery for SSE streams (e.g., daemon reconnecting after server restart)
          revoked_session = McpSession.find_by(session_token: session_id)
          if revoked_session&.reactivatable? && session_owned_by_current_principal?(revoked_session)
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
        # When client_instance_id is provided, tags the session so concurrent instances
        # each get their own session instead of sharing one.
        def auto_provision_mcp_session(client_instance_id: nil)
          app_id = @doorkeeper_token.application_id

          scope = McpSession.active
            .where(user: current_user, account: current_account, oauth_application_id: app_id)

          if client_instance_id.present?
            # Return session already tagged for this instance
            existing = scope.where("metadata->>'client_instance_id' = ?", client_instance_id).first
            return existing if existing

            # Claim an untagged session (legacy or freshly created by another path)
            existing = scope.where("metadata->>'client_instance_id' IS NULL OR metadata->>'client_instance_id' = ''").first
            if existing
              existing.update_column(:metadata, existing.metadata.merge("client_instance_id" => client_instance_id))
              return existing
            end
            # All existing sessions belong to other instances — create a new one
          else
            # Legacy: return any existing (backward compat for clients without instance ID)
            existing = scope.first
            return existing if existing
          end

          app_name = @doorkeeper_token.application&.name || "MCP Client"
          instance_metadata = client_instance_id.present? ? { "client_instance_id" => client_instance_id } : {}

          session = McpSession.create!(
            user: current_user,
            account: current_account,
            protocol_version: MCP_PROTOCOL_VERSION,
            client_info: { "name" => app_name, "version" => "auto-provisioned" },
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            expires_at: SESSION_TTL.from_now,
            oauth_application_id: app_id,
            metadata: instance_metadata
          )

          # include_grace_period: true — this IS the recovery flow for a disconnected
          # client. Allow reuse of agents whose session is in the grace period so the
          # daemon reclaims its original identity (e.g., "Claude Code (powernode) #1")
          # instead of creating a new #N+1.
          resolve_and_link_agent(session, include_grace_period: true)

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
        # @param include_grace_period [Boolean] passed through to identity service;
        #   true during auto-provisioning to allow reclaiming a temporarily-orphaned agent.
        # @param client_info [Hash] MCP client_info for provider detection.
        def resolve_and_link_agent(session, include_grace_period: false, client_info: {})
          return nil unless @doorkeeper_token

          ::Ai::McpClientIdentityService.new(
            account: current_account,
            user: current_user,
            doorkeeper_token: @doorkeeper_token,
            include_grace_period: include_grace_period,
            client_info: client_info
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

        # Owner attributes for a NEW McpSession. User (OAuth/CLI) principals keep
        # the existing { user: current_user } shape byte-for-byte; restricted
        # principals (instance mTLS or federation, no User) record
        # principal_kind + principal_subject_id instead, so the session is
        # attributable and NOT lumped with every other null-user session — which
        # is what session ownership checks and session/discover rely on. (BUG-Q)
        def session_principal_attributes
          return { user: current_user } if current_user

          if current_mcp_principal&.restricted?
            { user: nil, principal_kind: current_mcp_principal.kind.to_s,
              principal_subject_id: current_mcp_principal.subject_id }
          else
            { user: current_user }
          end
        end

        # A session belongs to the current principal iff it is in the current
        # account AND its owner matches: user_id for a user, or (kind, subject)
        # for a restricted principal. Prevents one principal from reading,
        # reclaiming or revoking another's session by presenting its token.
        def session_owned_by_current_principal?(session)
          return false unless session
          return false unless session.account_id == current_account&.id

          if current_mcp_principal&.restricted?
            session.principal_kind == current_mcp_principal.kind.to_s &&
              session.principal_subject_id.to_s == current_mcp_principal.subject_id.to_s
          elsif current_user
            session.user_id == current_user.id
          else
            false
          end
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

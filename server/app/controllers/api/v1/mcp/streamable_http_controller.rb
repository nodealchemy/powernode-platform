# frozen_string_literal: true

module Api
  module V1
    module Mcp
      class StreamableHttpController < ApplicationController
        include McpTokenAuthentication

        MCP_PROTOCOL_VERSION = "2025-06-18"
        SESSION_TTL = 24.hours

        skip_before_action :authenticate_request
        before_action :authenticate_mcp_request
        before_action :set_mcp_headers
        before_action :track_session_activity

        # POST /api/v1/mcp/message
        # Handles all JSON-RPC 2.0 MCP messages
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

        def handle_initialize(params, _message_id)
          client_version = params["protocolVersion"]
          negotiated = ::Mcp::ProtocolService.negotiate_protocol_version(client_version)

          unless negotiated
            render_jsonrpc_error(nil, -32602, "Unsupported protocol version: #{client_version}")
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

          { "tools" => (agent_tools["tools"] || []) + platform_tools }
        end

        def handle_tools_call(params)
          tool_name = params["name"]
          arguments = params["arguments"] || {}

          unless tool_name.present?
            render_jsonrpc_error(nil, -32602, "Missing required parameter: name")
            return nil
          end

          # Route platform tools directly to McpPlatformToolRegistrar
          # (bypasses RegistryService in-memory lookup which doesn't persist platform tools)
          if tool_name.start_with?("platform.")
            result = ::Ai::Tools::McpPlatformToolRegistrar.execute_tool(
              tool_name,
              params: arguments,
              account: current_account,
              user: current_user,
              token: @mcp_token
            )
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
          {
            content: [
              { type: "text", text: result.to_json }
            ]
          }
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
          return { "type" => "object", "properties" => {} } if parameters.blank?

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

        def current_user
          @current_user
        end

        def current_account
          @current_account
        end
      end
    end
  end
end

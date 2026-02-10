# frozen_string_literal: true

# Api::V1::A2aController - JSON-RPC 2.0 endpoint for A2A protocol communication
# Implements the A2A protocol specification for agent-to-agent interoperability
module Api
  module V1
    class A2aController < ActionController::API
      include ActionController::Live

      # POST /api/v1/a2a
      # JSON-RPC 2.0 endpoint for A2A operations
      def handle
        request_body = parse_request_body
        return unless request_body

        # Validate JSON-RPC 2.0 format
        unless valid_jsonrpc_request?(request_body)
          return render_jsonrpc_error(-32600, "Invalid Request", nil)
        end

        method = request_body["method"]
        params = request_body["params"] || {}
        id = request_body["id"]

        # Route to appropriate handler
        result = dispatch_method(method, params)

        if result[:error]
          render_jsonrpc_error(result[:error][:code], result[:error][:message], id, result[:error][:data])
        else
          render_jsonrpc_success(result[:result], id)
        end
      rescue StandardError => e
        Rails.logger.error("A2A JSON-RPC error: #{e.message}")
        render_jsonrpc_error(-32603, "Internal error", request_body&.dig("id"))
      end

      # GET /api/v1/a2a (info endpoint)
      def info
        render json: {
          protocol: "a2a",
          version: "1.0.0",
          supported_methods: A2a::MessageHandler::SUPPORTED_METHODS,
          agent_card_url: "#{request.base_url}/.well-known/agent-card.json",
          documentation: "https://a2a-protocol.org/latest/specification/"
        }
      end

      # POST /api/v1/a2a/stream
      # SSE streaming endpoint for message/stream operations
      def stream
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"
        response.headers["Connection"] = "keep-alive"

        request_body = parse_request_body
        return unless request_body

        params = request_body["params"] || {}
        id = request_body["id"]

        # Authenticate the request
        account = authenticate_request
        unless account
          write_sse_event({ error: { code: -32001, message: "Authentication required" } }, "error")
          return
        end

        handler = A2a::MessageHandler.new(account: account)
        handler.stream_message(params, response.stream) do |event|
          write_sse_event(event, event[:type] || "message")
        end
      rescue ActionController::Live::ClientDisconnected
        Rails.logger.info("A2A stream client disconnected")
      rescue StandardError => e
        Rails.logger.error("A2A stream error: #{e.message}")
        write_sse_event({ error: { code: -32603, message: "Stream error" } }, "error")
      ensure
        response.stream.close rescue nil
      end

      private

      def parse_request_body
        body = request.body.read
        return {} if body.blank?
        JSON.parse(body)
      rescue JSON::ParserError
        render_jsonrpc_error(-32700, "Parse error", nil)
        nil
      end

      def valid_jsonrpc_request?(req)
        req.is_a?(Hash) &&
          req["jsonrpc"] == "2.0" &&
          req["method"].is_a?(String)
      end

      def dispatch_method(method, params)
        account = authenticate_request
        return { error: { code: -32001, message: "Authentication required" } } unless account

        handler = A2a::MessageHandler.new(account: account)

        case method
        when "message/send"
          handler.send_message(params)
        when "message/stream"
          { error: { code: -32001, message: "Use /api/v1/a2a/stream endpoint for streaming" } }
        when "tasks/get"
          handler.get_task(params)
        when "tasks/list"
          handler.list_tasks(params)
        when "tasks/cancel"
          handler.cancel_task(params)
        when "tasks/subscribe"
          handler.subscribe_task(params)
        when "tasks/pushNotification/set"
          handler.set_push_notification(params)
        when "tasks/pushNotification/get"
          handler.get_push_notification(params)
        when "agent/authenticatedExtendedCard"
          handler.get_extended_card(params)
        else
          { error: { code: -32601, message: "Method not found", data: { method: method } } }
        end
      end

      def authenticate_request
        # Try Bearer token authentication
        auth_header = request.headers["Authorization"]
        if auth_header&.start_with?("Bearer ")
          token = auth_header.split(" ").last
          return authenticate_jwt_token(token)
        end

        # Try API key authentication
        api_key = request.headers["X-API-Key"]
        if api_key.present?
          return authenticate_api_key(api_key)
        end

        nil
      end

      def authenticate_jwt_token(token)
        decoded = Security::JwtService.decode(token)
        return nil unless decoded

        user = User.find_by(id: decoded[:user_id])
        user&.account
      rescue StandardError
        nil
      end

      def authenticate_api_key(key)
        api_key = ApiKey.find_by_key(key)
        return nil unless api_key&.active?

        api_key.record_usage!
        api_key.account
      rescue StandardError
        nil
      end

      def render_jsonrpc_success(result, id)
        render json: {
          jsonrpc: "2.0",
          result: result,
          id: id
        }
      end

      def render_jsonrpc_error(code, message, id, data = nil)
        error = { code: code, message: message }
        error[:data] = data if data.present?

        render json: {
          jsonrpc: "2.0",
          error: error,
          id: id
        }
      end

      def write_sse_event(data, event_type)
        message = "event: #{event_type}\n"
        message += "data: #{data.to_json}\n\n"
        response.stream.write(message)
      end
    end
  end
end

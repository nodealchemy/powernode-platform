# frozen_string_literal: true

# Api::V1::A2aController - JSON-RPC 2.0 endpoint for A2A protocol communication
# Implements the A2A protocol specification for agent-to-agent interoperability
module Api
  module V1
    class A2aController < ActionController::API
      include ActionController::Live

      # Who is calling, as BOTH halves. The account alone was all this endpoint
      # used to carry, and it is why no A2A skill could apply a per-user check
      # (IMP-01a07d5a): authenticate_jwt_token resolved a real User and then
      # returned `user&.account`, discarding the identity it had just proved.
      # A2a::MessageHandler and every skill under A2a::Skills already accept
      # `user:` and thread it down — A2a::Skills::MemorySkills#authorize! is
      # written, parameterised per skill, and returns early on a nil user, so
      # it could never refuse anything. Its comment named this controller as
      # the reason.
      #
      # `user` is legitimately nil for an API-key principal: an ApiKey belongs
      # to an account and carries SCOPES, with no owning user, so there is no
      # identity to pass. Never infer one from the account — a nil user means
      # "no user", which is exactly what BaseTool documents against conflating
      # with "internal" (base_tool.rb:384-390, IMP-9030413bc292).
      Principal = Struct.new(:account, :user, keyword_init: true)

      # Usage is recorded AFTER the action, where the response status exists.
      # It used to be recorded inside the authenticator, which runs before the
      # action and therefore passed nil into api_key_usages' NOT NULL
      # response_status — one of the reasons no row was ever written
      # (IMP-01a07d5a). Recording it here also takes it off the authentication
      # path: a bookkeeping failure must never be able to reject a valid key,
      # which is exactly what the authenticator's `rescue StandardError => nil`
      # was silently doing.
      after_action :record_api_key_usage, only: %i[handle stream]

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
        principal = authenticate_request
        unless principal
          write_sse_event({ error: { code: -32001, message: "Authentication required" } }, "error")
          return
        end

        handler = A2a::MessageHandler.new(account: principal.account, user: principal.user)
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
        principal = authenticate_request
        return { error: { code: -32001, message: "Authentication required" } } unless principal

        handler = A2a::MessageHandler.new(account: principal.account, user: principal.user)

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
        return nil unless user&.account

        Principal.new(account: user.account, user: user)
      rescue StandardError
        nil
      end

      def authenticate_api_key(key)
        api_key = ApiKey.find_by_key(key)
        return nil unless api_key&.active?

        @authenticated_api_key = api_key
        Principal.new(account: api_key.account, user: nil)
      rescue StandardError
        nil
      end

      # Best-effort by construction: the response is already rendered, so a
      # failure here can only be logged. Never re-raise — the caller has been
      # served, and losing a usage row must not turn a successful response into
      # a 500.
      def record_api_key_usage
        return if @authenticated_api_key.nil?

        @authenticated_api_key.record_usage!(
          endpoint: request.path,
          method: request.request_method,
          status: response.status,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      rescue StandardError => e
        Rails.logger.warn("A2A api-key usage not recorded: #{e.class}: #{e.message}")
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

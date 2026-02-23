# frozen_string_literal: true

module Mcp
  # Broadcasts MCP-standard JSON-RPC 2.0 notifications to session pubsub channels.
  # Consumed by the GET SSE stream in StreamableHttpController.
  #
  # Uses ActionCable's low-level pubsub (not channels) to match how the SSE
  # stream subscribes via pubsub.subscribe.
  class SessionNotifier
    # Notify all active MCP sessions for an account that the tool list changed.
    # Clients receiving this should re-fetch tools/list.
    def self.notify_tools_changed(account)
      broadcast_to_account_sessions(account, "notifications/tools/list_changed")
    end

    # Notify all active MCP sessions for an account that the resource list changed.
    # Clients receiving this should re-fetch resources/list.
    def self.notify_resources_changed(account)
      broadcast_to_account_sessions(account, "notifications/resources/list_changed")
    end

    # Broadcast a JSON-RPC 2.0 notification to a single session's channel.
    def self.notify_session(session, method, params = nil)
      payload = { jsonrpc: "2.0", method: method }
      payload[:params] = params if params.present?

      channel = "mcp_session:#{session.session_token}"
      ActionCable.server.pubsub.broadcast(channel, payload.to_json)
    end

    def self.broadcast_to_account_sessions(account, method, params = nil)
      payload = { jsonrpc: "2.0", method: method }
      payload[:params] = params if params.present?
      json = payload.to_json

      McpSession.active.where(account: account).find_each do |session|
        channel = "mcp_session:#{session.session_token}"
        ActionCable.server.pubsub.broadcast(channel, json)
      end
    rescue StandardError => e
      Rails.logger.warn "[Mcp::SessionNotifier] Broadcast failed for #{method}: #{e.message}"
    end

    private_class_method :broadcast_to_account_sessions
  end
end

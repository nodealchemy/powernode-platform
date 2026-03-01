# frozen_string_literal: true

module Ai
  module Autonomy
    class ClaudeSessionDiscoveryService
      ACTIVITY_WINDOW = 5.minutes

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Find active Claude Code MCP client sessions.
      #
      # @return [Array<Hash>] list of active sessions with agent and session info
      def active_sessions
        sessions = McpSession
          .where(account_id: account.id, status: "active")
          .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
          .includes(:ai_agent)

        sessions.filter_map do |session|
          agent = session.ai_agent
          next unless agent&.agent_type == "mcp_client"

          {
            session_id: session.id,
            agent_id: agent.id,
            agent_name: agent.name,
            last_activity_at: session.last_activity_at&.iso8601,
            connected_since: session.created_at.iso8601,
            capabilities: extract_capabilities(session)
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[ClaudeSessionDiscovery] Failed: #{e.message}")
        []
      end

      # Check if any active Claude session exists
      def any_active?
        active_sessions.any?
      end

      # Find the most recently active session
      def most_recent_session
        active_sessions.max_by { |s| s[:last_activity_at] }
      end

      private

      def extract_capabilities(session)
        metadata = session.metadata || {}
        metadata["capabilities"] || []
      rescue StandardError
        []
      end
    end
  end
end

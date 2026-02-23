# frozen_string_literal: true

module Ai
  class McpClientIdentityService
    def initialize(account:, user:, doorkeeper_token:)
      @account = account
      @user = user
      @doorkeeper_token = doorkeeper_token
    end

    # Resolves or creates an Ai::Agent identity for this MCP session.
    # Returns the agent record.
    def resolve_agent
      return @cached_agent if defined?(@cached_agent)

      @cached_agent = find_existing_agent || create_mcp_agent
    end

    # Deactivates the agent associated with an MCP session
    def self.deactivate_agent(mcp_session)
      return unless mcp_session.ai_agent&.active?
      return unless mcp_session.ai_agent.agent_type == "mcp_client"

      mcp_session.ai_agent.update(status: "inactive")
    end

    private

    attr_reader :account, :user, :doorkeeper_token

    def oauth_application_id
      doorkeeper_token.application_id
    end

    def oauth_application
      @oauth_application ||= doorkeeper_token.application
    end

    # Find an existing active MCP client agent for this OAuth app.
    # First checks active sessions (fast path), then falls back to checking
    # agent metadata (handles token refresh / new sessions for the same app).
    def find_existing_agent
      # Fast path: find via active session with matching OAuth app
      scope = McpSession.active
        .where(account: account, user: user)
        .where.not(ai_agent_id: nil)

      scope = scope.where(oauth_application_id: oauth_application_id) if oauth_application_id.present?

      session = scope.order(last_activity_at: :desc).first
      return session.ai_agent if session&.ai_agent&.active?

      # Fallback: find active mcp_client agent by OAuth app metadata
      # Prevents creating duplicate agents when tokens are refreshed
      if oauth_application_id.present?
        agent = account.ai_agents
          .where(agent_type: "mcp_client", status: "active")
          .where("mcp_metadata->>'oauth_application_id' = ?", oauth_application_id)
          .order(created_at: :desc)
          .first

        return agent if agent
      end

      nil
    end

    def create_mcp_agent
      app_name = oauth_application&.name || "MCP Client"
      sequence = next_sequence_number(app_name)
      agent_name = "#{app_name} ##{sequence}"

      # Find a default provider for the account
      provider = account.ai_providers.where(is_active: true).order(:created_at).first
      return nil unless provider

      agent = Ai::Agent.create!(
        account: account,
        creator: user,
        name: agent_name,
        description: "Auto-created identity for #{app_name} MCP session",
        agent_type: "mcp_client",
        status: "active",
        provider: provider,
        version: "1.0.0",
        mcp_metadata: {
          oauth_application_id: oauth_application_id,
          oauth_application_name: app_name,
          created_by_user_id: user.id
        }
      )

      Rails.logger.info "[McpClientIdentityService] Created MCP client agent: #{agent.name} (#{agent.id}) for user #{user.id}"
      agent
    rescue StandardError => e
      Rails.logger.error "[McpClientIdentityService] Failed to create agent: #{e.class}: #{e.message}"
      nil
    end

    def next_sequence_number(app_name)
      # Count existing mcp_client agents for this account with matching app name prefix
      existing = account.ai_agents
        .where(agent_type: "mcp_client")
        .where("name LIKE ?", "#{app_name} #%")
        .count

      existing + 1
    end
  end
end

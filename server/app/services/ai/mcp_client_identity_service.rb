# frozen_string_literal: true

module Ai
  class McpClientIdentityService
    def initialize(account:, user:, doorkeeper_token:)
      @account = account
      @user = user
      @doorkeeper_token = doorkeeper_token
    end

    # Creates a fresh Ai::Agent identity for this MCP session.
    # MCP client agents are transient — always created new, never reused.
    def resolve_agent
      return @cached_agent if defined?(@cached_agent)

      @cached_agent = create_mcp_agent
    end

    # Archives the MCP client agent and removes it from workspace teams
    def self.deactivate_agent(mcp_session)
      agent = mcp_session.ai_agent
      return unless agent&.active?
      return unless agent.mcp_client?

      agent.update!(status: "archived")
      remove_from_workspace_teams(agent)
      Rails.logger.info "[McpClientIdentityService] Archived MCP agent: #{agent.name} (#{agent.id})"
    end

    def self.remove_from_workspace_teams(agent)
      Ai::AgentTeamMember.joins(:team)
        .where(ai_agent_id: agent.id, ai_agent_teams: { team_type: "workspace" })
        .destroy_all
    end

    private

    attr_reader :account, :user, :doorkeeper_token

    def oauth_application_id
      doorkeeper_token.application_id
    end

    def oauth_application
      @oauth_application ||= doorkeeper_token.application
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

      auto_join_workspace_teams(agent)
      Rails.logger.info "[McpClientIdentityService] Created MCP client agent: #{agent.name} (#{agent.id}) for user #{user.id}"
      agent
    rescue StandardError => e
      Rails.logger.error "[McpClientIdentityService] Failed to create agent: #{e.class}: #{e.message}"
      nil
    end

    def auto_join_workspace_teams(agent)
      account.ai_agent_teams.where(team_type: "workspace", status: "active").find_each do |team|
        next if team.members.exists?(ai_agent_id: agent.id)
        Ai::AgentTeamMember.create!(
          ai_agent_team_id: team.id, ai_agent_id: agent.id,
          role: "executor", capabilities: ["code_execution", "system_commands", "file_operations"]
        )
      end
    rescue StandardError => e
      Rails.logger.warn "[McpClientIdentityService] Auto-join workspace failed: #{e.message}"
    end

    def next_sequence_number(app_name)
      # Extract max sequence number from all agents (including archived) to ensure uniqueness
      max_seq = account.ai_agents
        .where(agent_type: "mcp_client")
        .where("name LIKE ?", "#{app_name} #%")
        .pluck(:name)
        .filter_map { |n| n[/#{Regexp.escape(app_name)} #(\d+)\z/, 1]&.to_i }
        .max
      (max_seq || 0) + 1
    end

  end
end

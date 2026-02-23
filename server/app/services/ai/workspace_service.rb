# frozen_string_literal: true

module Ai
  class WorkspaceService
    def initialize(account:, user:)
      @account = account
      @user = user
    end

    # Creates a workspace: an AgentTeam + collaborative Conversation
    def create_workspace(name:, agent_ids: [])
      concierge = account.ai_agents.default_concierge.first
      raise ArgumentError, "Cannot create workspace: no active concierge agent exists for this account" unless concierge

      # Recover orphaned workspace team (team exists but conversation was lost)
      existing_team = account.ai_agent_teams.find_by(name: name, team_type: "workspace")
      if existing_team
        conversation = Ai::Conversation.find_by(agent_team_id: existing_team.id)
        if conversation
          return { team: existing_team, conversation: conversation }
        else
          # Orphaned team — create its missing conversation
          auto_add_concierge(existing_team)
          conversation = create_workspace_conversation(existing_team, name)
          return { team: existing_team, conversation: conversation }
        end
      end

      ActiveRecord::Base.transaction do
        team = create_workspace_team(name)
        add_agents_to_team(team, agent_ids)
        auto_add_concierge(team)
        conversation = create_workspace_conversation(team, name)

        { team: team, conversation: conversation }
      end
    end

    # Invite an agent to an existing workspace
    def invite_agent(workspace_conversation:, agent:)
      team = workspace_conversation.agent_team
      raise ArgumentError, "Not a workspace conversation" unless team&.team_type == "workspace"
      raise ArgumentError, "Agent already in workspace" if team.members.exists?(ai_agent_id: agent.id)

      role = agent.agent_type == "mcp_client" ? "executor" : "facilitator"
      team.add_member(agent: agent, role: role)

      broadcast_workspace_event(workspace_conversation, "agent_joined", {
        agent_id: agent.id,
        agent_name: agent.name,
        agent_type: agent.agent_type
      })

      team.members.find_by(ai_agent_id: agent.id)
    end

    # Remove an agent from a workspace
    def remove_agent(workspace_conversation:, agent:)
      team = workspace_conversation.agent_team
      raise ArgumentError, "Not a workspace conversation" unless team&.team_type == "workspace"

      member = team.members.find_by(ai_agent_id: agent.id)
      raise ArgumentError, "Agent not in workspace" unless member
      raise ArgumentError, "Cannot remove the concierge agent from a workspace" if agent.is_concierge?

      member.destroy!

      broadcast_workspace_event(workspace_conversation, "agent_left", {
        agent_id: agent.id,
        agent_name: agent.name
      })

      true
    end

    # List active MCP sessions with their agent identities
    def active_mcp_sessions(user: nil)
      scope = McpSession.active
        .where(account: account)
        .includes(:ai_agent, :oauth_application, :user)
        .where.not(ai_agent_id: nil)
        .order(last_activity_at: :desc)

      scope = scope.where(user: user) if user
      scope
    end

    # List workspace conversations for the current user
    def list_workspaces
      Ai::Conversation.where(account: account)
        .joins(:agent_team)
        .where(ai_agent_teams: { team_type: "workspace" })
        .where("ai_conversations.user_id = ? OR ai_conversations.is_collaborative = ?", user.id, true)
        .includes(:agent_team, :messages)
        .order(last_activity_at: :desc)
    end

    private

    attr_reader :account, :user

    def create_workspace_team(name)
      Ai::AgentTeam.create!(
        account: account,
        name: name,
        team_type: "workspace",
        coordination_strategy: "round_robin",
        status: "active",
        team_config: { workspace_owner_id: user.id }
      )
    end

    def add_agents_to_team(team, agent_ids)
      agent_ids.each do |agent_id|
        agent = account.ai_agents.find_by(id: agent_id)
        next unless agent&.active?

        role = agent.agent_type == "mcp_client" ? "executor" : "facilitator"
        team.add_member(agent: agent, role: role)
      end
    end

    def auto_add_concierge(team)
      concierge = account.ai_agents.default_concierge.first
      return unless concierge
      return if team.members.exists?(ai_agent_id: concierge.id)

      team.add_member(agent: concierge, role: "facilitator", is_lead: true)
    end

    def create_workspace_conversation(team, name)
      # Prefer the concierge/lead agent for message routing, fall back to first agent
      primary_agent = team.lead_agent || team.agents.first
      provider = primary_agent&.provider || account.ai_providers.where(is_active: true).order(:created_at).first
      raise ArgumentError, "No active AI provider available" unless provider

      Ai::Conversation.create!(
        account: account,
        user: user,
        agent_team: team,
        agent: primary_agent,
        ai_provider_id: provider.id,
        conversation_type: "team",
        is_collaborative: true,
        title: name,
        status: "active",
        participants: [user.id],
        last_activity_at: Time.current
      )
    end

    def broadcast_workspace_event(conversation, event_type, data)
      return unless conversation.websocket_channel.present?

      ActionCable.server.broadcast(
        conversation.websocket_channel,
        {
          type: event_type,
          conversation_id: conversation.conversation_id,
          data: data,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end

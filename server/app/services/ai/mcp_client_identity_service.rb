# frozen_string_literal: true

module Ai
  class McpClientIdentityService
    def initialize(account:, user:, doorkeeper_token:)
      @account = account
      @user = user
      @doorkeeper_token = doorkeeper_token
    end

    # Resolves or creates an Ai::Agent identity for this MCP client.
    # Reuses an orphaned agent (no active session) for the same OAuth application,
    # enabling stable identity across reconnections while assigning fresh agents
    # to concurrent instances.
    #
    # Uses a PostgreSQL advisory lock scoped to the account to serialize concurrent
    # identity resolution. Without this, two simultaneous `initialize` requests
    # both see zero orphaned agents, both compute sequence #1, and the second
    # fails on the name uniqueness constraint.
    # When called with a block, the block receives the agent and executes inside
    # the advisory lock transaction — use this to bind the agent to a session
    # atomically (before the lock releases), preventing another request from
    # seeing the agent as orphaned.
    def resolve_agent(&block)
      return @cached_agent if defined?(@cached_agent)

      @cached_agent = with_identity_lock do
        agent = find_existing_agent || create_mcp_agent
        yield agent if agent && block_given?
        agent
      end
    end

    # Soft-deactivates an MCP client agent when its session ends.
    # MCP client agents are persistent — they survive session lifecycle and are
    # reused on reconnect via find_existing_agent. This method is intentionally
    # a no-op beyond logging: the agent stays active with its workspace team
    # memberships, conversation/message FKs, and sequence number intact.
    def self.deactivate_agent(mcp_session)
      agent = mcp_session.ai_agent
      return unless agent&.active? && agent.mcp_client?

      Rails.logger.info "[McpClientIdentityService] MCP agent orphaned (session ended): #{agent.name} (#{agent.id})"
    end

    # Force-destroys an MCP client agent and cleans up all references.
    # Used for explicit cleanup (rake task, admin action) — not during normal
    # session lifecycle. Nullifies FKs on conversations/messages/sessions and
    # removes all team memberships before destroying.
    def self.force_deactivate_agent(mcp_session)
      agent = mcp_session.ai_agent
      return unless agent&.mcp_client?

      agent_id = agent.id
      agent_name = agent.name

      Ai::Conversation.where(ai_agent_id: agent_id).update_all(ai_agent_id: nil)
      Ai::Message.where(ai_agent_id: agent_id).update_all(ai_agent_id: nil)
      McpSession.where(ai_agent_id: agent_id).update_all(ai_agent_id: nil)

      Ai::AgentTeamMember.where(ai_agent_id: agent_id).destroy_all
      agent.destroy!

      Rails.logger.info "[McpClientIdentityService] Force-destroyed MCP agent: #{agent_name} (#{agent_id})"
    end

    def self.remove_from_workspace_teams(agent)
      Ai::AgentTeamMember.joins(:team)
        .where(ai_agent_id: agent.id, ai_agent_teams: { team_type: "workspace" })
        .destroy_all
    end

    private

    attr_reader :account, :user, :doorkeeper_token

    # PostgreSQL advisory lock keyed on account ID to serialize concurrent
    # resolve_agent calls for the same account. Uses pg_advisory_xact_lock
    # (transaction-scoped) so the lock auto-releases on commit/rollback.
    # The lock key combines a namespace constant with the account's hash_value
    # to avoid collisions with other advisory lock users.
    IDENTITY_LOCK_NAMESPACE = 0x4D435049 # "MCPI" in hex

    def with_identity_lock(&block)
      lock_key = account.id.hash & 0x7FFFFFFF # Ensure positive 32-bit int
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(#{IDENTITY_LOCK_NAMESPACE}, #{lock_key})"
        )
        yield
      end
    rescue ActiveRecord::RecordNotUnique
      # Safety net: if two requests slip past the advisory lock (e.g., different
      # connection pools), retry once — the second attempt will find the agent
      # created by the first request via find_existing_agent.
      Rails.logger.warn "[McpClientIdentityService] RecordNotUnique on agent creation, retrying..."
      find_existing_agent || create_mcp_agent
    end

    def find_existing_agent
      # Agents with real (non-auto-provisioned) active sessions are occupied by
      # a live client and must not be reused. But agents whose ONLY active session
      # is auto-provisioned are still available — they're placeholders awaiting a
      # real client (created by session/discover self-healing).
      real_active_agent_ids = McpSession.active
        .where.not(ai_agent_id: nil)
        .where("client_info->>'version' IS DISTINCT FROM ?", "auto-provisioned")
        .select(:ai_agent_id)
      grace_agent_ids = McpSession.in_grace_period
        .where.not(ai_agent_id: nil).select(:ai_agent_id)

      account.ai_agents
        .where(agent_type: "mcp_client", status: "active")
        .where("mcp_metadata->>'oauth_application_id' = ?", oauth_application_id.to_s)
        .where.not(id: real_active_agent_ids)
        .where.not(id: grace_agent_ids)
        .order(created_at: :desc)
        .first
    end

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

      Rails.logger.info "[McpClientIdentityService] Created MCP client agent: #{agent.name} (#{agent.id}) for user #{user.id}"
      restore_workspace_memberships(agent)
      agent
    end

    # When a new MCP agent is created (after the previous one was force-destroyed),
    # restore membership in workspace teams that have no other mcp_client agent.
    # This prevents the "dead workspace" state where the concierge can't delegate
    # because no mcp_client is in the team.
    def restore_workspace_memberships(agent)
      workspace_teams = Ai::AgentTeam.where(account: account, team_type: "workspace")
      workspace_teams.each do |team|
        has_mcp_client = team.members.joins(:agent)
          .where(ai_agents: { agent_type: "mcp_client", status: "active" }).exists?
        next if has_mcp_client

        team.add_member(agent: agent, role: "executor")
        Rails.logger.info "[McpClientIdentityService] Restored #{agent.name} to workspace team: #{team.name} (#{team.id})"
      end
    rescue StandardError => e
      Rails.logger.warn "[McpClientIdentityService] Failed to restore workspace memberships: #{e.message}"
    end

    def next_sequence_number(app_name)
      # Find the lowest available sequence number across ALL agents (any status).
      # Must check all statuses because name uniqueness is enforced account-wide.
      # MCP client agents persist across sessions (not destroyed on deactivation)
      # and are reused via find_existing_agent, so their numbers stay occupied.
      # Only force_deactivate_agent (rake task / admin) frees a slot.
      used = account.ai_agents
        .where(agent_type: "mcp_client")
        .where("name LIKE ?", "#{app_name} #%")
        .pluck(:name)
        .filter_map { |n| n[/#{Regexp.escape(app_name)} #(\d+)\z/, 1]&.to_i }
        .sort

      seq = 1
      used.each do |n|
        break if n != seq
        seq += 1
      end
      seq
    end

  end
end

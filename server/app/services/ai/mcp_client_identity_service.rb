# frozen_string_literal: true

module Ai
  class McpClientIdentityService
    # Raised inside a merge's transaction when a duplicate stopped being
    # mergeable after the report listed it; the merge loop records it as an error.
    class MergeSkipped < StandardError; end

    # @param client_info [Hash] MCP client_info from the initialize handshake.
    #   Used to detect the correct AI provider (e.g., "Anthropic's agentic coding
    #   tool" → anthropic provider). Falls back to OAuth application name if empty.
    def initialize(account:, user:, doorkeeper_token:, client_info: {})
      @account = account
      @user = user
      @doorkeeper_token = doorkeeper_token
      @client_info = client_info || {}
    end

    # Resolves or creates the Ai::Agent identity for this MCP client.
    # There is one identity per (OAuth client name, user) within an account,
    # shared by every session of that client: concurrent instances, restarts,
    # and re-registrations (dynamic client registration mints a new OAuth
    # application each time, under the same name). A new "<client> #N" agent
    # is only minted when the user has no identity for that client yet.
    #
    # Same client name ⇒ same identity: any OAuth application registered under
    # that name, by that user, resolves to this agent. Because concurrent
    # instances share it, anything addressed to the agent (workspace @mentions,
    # workspace channel events) fans out to every concurrent instance.
    #
    # Uses a PostgreSQL advisory lock scoped to the account to serialize concurrent
    # identity resolution. Without this, two simultaneous `initialize` requests
    # both find no identity and both create one.
    # When called with a block, the block receives the agent and executes inside
    # the advisory lock transaction — use this to bind the agent to a session
    # atomically (before the lock releases).
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

    # Archives an MCP client agent that has no live session: drops its
    # workspace seats (so workspaces don't route to an absent client) but
    # records them in mcp_metadata, so find_existing_agent can give them back
    # on reconnect even when another MCP client now sits in that workspace.
    ARCHIVED_SEATS_KEY = "archived_workspace_team_ids"

    def self.archive_agent!(agent)
      seat_team_ids = Ai::AgentTeamMember.joins(:team)
        .where(ai_agent_id: agent.id, ai_agent_teams: { team_type: "workspace" })
        .pluck(:ai_agent_team_id)
      metadata = (agent.mcp_metadata || {}).merge(ARCHIVED_SEATS_KEY => seat_team_ids)
      agent.update!(status: "archived", mcp_metadata: metadata)
      remove_from_workspace_teams(agent)
    end

    def self.remove_from_workspace_teams(agent)
      Ai::AgentTeamMember.joins(:team)
        .where(ai_agent_id: agent.id, ai_agent_teams: { team_type: "workspace" })
        .destroy_all
    end

    REUSABLE_STATUSES = %w[active archived].freeze

    def self.identity_candidates(scope)
      scope.where(agent_type: "mcp_client", status: REUSABLE_STATUSES)
    end

    # Order in which one identity is chosen among several for the same
    # (client, user): active before archived, then the lowest "#N", then oldest.
    # Shared by resolution and duplicate cleanup so both keep the same agent.
    def self.canonical_order(agents)
      agents.to_a.sort_by do |a|
        [ a.status == "active" ? 0 : 1, a.name[/ #(\d+)\z/, 1]&.to_i || Float::INFINITY, a.created_at ]
      end
    end

    # Reports MCP client identities duplicated per (account, client name, user),
    # e.g. the "Claude Code (headersHelper) #1-#13" left behind before identities
    # were shared across sessions. Read-only.
    #   count/first/last — the duplicates a confirmed merge would remove
    #   skipped          — duplicates left alone (live session, a live deferred
    #                      operation, or a manual team)
    def self.duplicate_agents_report(account: nil)
      groups = duplicate_groups(account).map do |(account_id, client_name, user_id), agents|
        keeper, *dups = canonical_order(agents)
        {
          account_id: account_id, client_name: client_name, user_id: user_id,
          keeper: agent_summary(keeper),
          duplicates: dups.map do |d|
            agent_summary(d).merge(drops: merge_drops(d), skip_reason: duplicate_skip_reason(d))
          end
        }
      end

      all_dups = groups.flat_map { |g| g[:duplicates] }
      removable = all_dups.reject { |d| d[:skip_reason] }
      {
        count: removable.size,
        first: removable.first(3),
        last: removable.last,
        skipped: all_dups.select { |d| d[:skip_reason] }.map { |d| d.except(:skip_reason).merge(reason: d[:skip_reason]) },
        groups: groups
      }
    end

    # Merges removable duplicates into their group's keeper: repoints sessions,
    # executions, conversations, messages and the other agent FKs, moves team
    # memberships, then destroys the duplicate. Does nothing unless confirm is
    # exactly true, so a caller must opt in after reading the report.
    def self.merge_duplicate_agents!(confirm:, account: nil)
      report = duplicate_agents_report(account: account)
      return report.merge(dry_run: true, merged: 0, errors: []) unless confirm == true

      merged = 0
      errors = []
      report[:groups].each do |group|
        keeper = Ai::Agent.find(group[:keeper][:id])
        group[:duplicates].reject { |d| d[:skip_reason] }.each do |dup|
          merge_agent_into!(Ai::Agent.find(dup[:id]), keeper)
          merged += 1
        rescue StandardError => e
          errors << { id: dup[:id], name: dup[:name], error: e.message }
          Rails.logger.warn "[McpClientIdentityService] Failed to merge #{dup[:name]} (#{dup[:id]}): #{e.message}"
        end
      end
      report.merge(dry_run: false, merged: merged, errors: errors)
    end

    def self.duplicate_groups(account)
      scope = identity_candidates(account ? account.ai_agents : Ai::Agent.all)
      scope.group_by do |agent|
        name = agent.mcp_metadata&.dig("oauth_application_name").presence || agent.name.sub(/ #\d+\z/, "")
        [ agent.account_id, name, agent.creator_id ]
      end.select { |_, agents| agents.size > 1 }
    end
    private_class_method :duplicate_groups

    # Counts, keyed "table.column", of the rows a merge deletes with the
    # duplicate instead of handing them to the keeper (non-zero only).
    def self.merge_drops(agent)
      connection = ActiveRecord::Base.connection
      MERGE_DROPPED_FKS.each_with_object({}) do |(table, col), drops|
        n = connection.select_value("SELECT COUNT(*) FROM #{table} WHERE #{col} = #{connection.quote(agent.id)}").to_i
        drops["#{table}.#{col}"] = n if n.positive?
      end
    end
    private_class_method :merge_drops

    def self.agent_summary(agent)
      { id: agent.id, name: agent.name, status: agent.status, created_at: agent.created_at }
    end
    private_class_method :agent_summary

    def self.duplicate_skip_reason(agent)
      return "live_session" if McpSession.live.where(ai_agent_id: agent.id).exists?
      # A live deferred operation's approval request and parked principal name
      # this agent, so after a merge it could no longer run as the identity
      # that asked for it.
      return "unsettled_operations" if Ai::DeferredOperation.where(ai_agent_id: agent.id,
                                                                     status: Ai::DeferredOperation::LIVE_STATUSES).exists?

      manual_team = Ai::AgentTeamMember.joins(:team).where(ai_agent_id: agent.id)
        .where.not(ai_agent_teams: { team_type: "workspace" }).exists?
      "manual_team" if manual_team
    end
    private_class_method :duplicate_skip_reason

    # How a merge treats every column that points at ai_agents. The spec
    # "merge foreign-key coverage" derives all FKs to ai_agents from the
    # database and fails on any column missing here, so a new FK cannot be
    # silently cascaded, nulled or left to RESTRICT the destroy.
    #
    # Repointed to the keeper, beyond AgentManagementTool::REASSIGN_AGENT_FKS:
    # the duplicate's work history. Executions, conversations and shadow
    # executions are dependent: :destroy on Ai::Agent, platform_investigations
    # is ON DELETE SET NULL, and the rest RESTRICT the destroy.
    MERGE_EXTRA_FKS = [
      [ "ai_agent_executions", "ai_agent_id" ],
      [ "ai_conversations", "ai_agent_id" ],
      [ "ai_memory_pools", "owner_agent_id" ],
      [ "ai_agent_goals", "ai_agent_id" ],
      [ "ai_worktrees", "ai_agent_id" ],
      [ "ai_shadow_executions", "agent_id" ],
      [ "ai_evaluation_results", "agent_id" ],
      [ "platform_investigations", "agent_id" ],
      [ "ai_team_roles", "ai_agent_id" ],
      [ "ai_agent_installations", "installed_agent_id" ],
      [ "ai_agent_templates", "source_agent_id" ]
    ].freeze

    # Repointed with pair dedup (unique parent/child, no self-lineage).
    MERGE_LINEAGE_FKS = [
      [ "ai_agent_lineages", "parent_agent_id" ],
      [ "ai_agent_lineages", "child_agent_id" ]
    ].freeze

    # Deleted with the duplicate and counted in the report's drops: per-agent
    # state that cannot be combined with the keeper's. Guardrail configs are
    # deleted rather than nulled because a NULL ai_agent_id makes a config the
    # account-wide default.
    MERGE_DESTROYED_FKS = [
      [ "ai_agent_short_term_memories", "agent_id" ],
      [ "ai_agent_skills", "ai_agent_id" ],
      [ "ai_agent_budgets", "agent_id" ],
      [ "ai_agent_trust_scores", "agent_id" ]
    ].freeze
    # A promotion grant is a person's permission for ONE agent, and it goes
    # when that agent does (the FK cascades). Repointing it would hand that
    # permission to a different agent nobody granted it to.
    MERGE_DELETE_FKS = [
      [ "ai_guardrail_configs", "ai_agent_id" ],
      [ "ai_promotion_grants", "ai_agent_id" ]
    ].freeze

    # Rows AgentManagementTool::DELETE_AGENT_ROWS deletes with a destroyed
    # agent, but a merge repoints to the keeper instead: they record what the
    # duplicate's identity did. Deferred operations are the gated actions it
    # ran (a duplicate with one still live is skipped, see
    # duplicate_skip_reason); proposals, escalations and feedback are its
    # decisions; goal plans, observations and team restructure events belong
    # to goals and teams the merge already repoints (deleting a plan with
    # steps would also violate ai_goal_plan_steps' FK). Deleting an agent ends
    # that identity, but a merge only folds one identity into another, so the
    # history stays. Merged feedback not yet applied to trust counts toward
    # the keeper's next trust batch, which is right for the same user+client
    # identity. A subset of DELETE_AGENT_ROWS, so nothing is both repointed
    # and deleted.
    MERGE_HISTORY_FKS = [
      [ "ai_deferred_operations", "ai_agent_id" ],
      [ "ai_agent_proposals", "ai_agent_id" ],
      [ "ai_agent_escalations", "ai_agent_id" ],
      [ "ai_agent_feedbacks", "ai_agent_id" ],
      [ "ai_goal_plans", "ai_agent_id" ],
      [ "ai_agent_observations", "ai_agent_id" ],
      [ "ai_team_restructure_events", "ai_agent_id" ]
    ].freeze
    MERGE_DELETED_AGENT_ROWS = (Ai::Tools::AgentManagementTool::DELETE_AGENT_ROWS - MERGE_HISTORY_FKS).freeze
    MERGE_DROPPED_FKS = (MERGE_DESTROYED_FKS + MERGE_DELETE_FKS + MERGE_DELETED_AGENT_ROWS).freeze

    def self.classified_agent_fks
      MERGE_EXTRA_FKS + MERGE_LINEAGE_FKS + MERGE_HISTORY_FKS + MERGE_DROPPED_FKS +
        Ai::Tools::AgentManagementTool::REASSIGN_AGENT_FKS
    end

    def self.merge_agent_into!(dup, keeper)
      connection = ActiveRecord::Base.connection
      ActiveRecord::Base.transaction do
        # The report's skip rules were evaluated before this transaction. Re-check
        # them under FOR UPDATE on the duplicate's row: a concurrent insert of a
        # row referencing it (a new deferred operation or session) needs FOR KEY
        # SHARE on that row, so it waits for this merge, and anything that
        # landed in between is seen here.
        dup.lock!
        reason = duplicate_skip_reason(dup)
        raise MergeSkipped, "no longer mergeable: #{reason}" if reason

        # Team memberships are unique per (team, agent): drop the duplicate's
        # seat where the keeper already sits, move the rest.
        keeper_team_ids = Ai::AgentTeamMember.where(ai_agent_id: keeper.id).select(:ai_agent_team_id)
        Ai::AgentTeamMember.where(ai_agent_id: dup.id, ai_agent_team_id: keeper_team_ids).delete_all

        merge_private_memory_pool!(dup, keeper)

        fks = MERGE_EXTRA_FKS + MERGE_HISTORY_FKS + Ai::Tools::AgentManagementTool::REASSIGN_AGENT_FKS
        fks.each do |table, col|
          connection.exec_update("UPDATE #{table} SET #{col} = $1 WHERE #{col} = $2",
                                 "merge-#{table}-#{col}", [ keeper.id, dup.id ])
        end
        McpSession.where(ai_agent_id: keeper.id).where("display_name IS DISTINCT FROM ?", keeper.name)
          .update_all(display_name: keeper.name)

        merge_lineages!(dup, keeper)

        # The grants go with the duplicate (see MERGE_DELETE_FKS): leave the
        # audit row for each before the rows disappear.
        Ai::PromotionGrant.where(ai_agent_id: dup.id).includes(:environment).find_each do |grant|
          Ai::PromotionGrants::Ledger.dropped_with_merged_agent!(grant, duplicate: dup, keeper: keeper)
        end

        (MERGE_DELETE_FKS + MERGE_DELETED_AGENT_ROWS).each do |table, col|
          connection.exec_delete("DELETE FROM #{table} WHERE #{col} = $1", "merge-del-#{table}-#{col}", [ dup.id ])
        end

        dup.reload.destroy!
      end
      Rails.logger.info "[McpClientIdentityService] Merged duplicate MCP agent #{dup.name} (#{dup.id}) into #{keeper.name} (#{keeper.id})"
    end
    private_class_method :merge_agent_into!

    # Lineage pairs are unique and an agent cannot be its own parent: drop the
    # pairs that would collapse onto the keeper or duplicate one it has, then
    # repoint the rest.
    def self.merge_lineages!(dup, keeper)
      connection = ActiveRecord::Base.connection
      d = connection.quote(dup.id)
      k = connection.quote(keeper.id)
      connection.exec_delete(<<~SQL.squish, "merge-lineage-dedup")
        DELETE FROM ai_agent_lineages l
        WHERE (l.parent_agent_id = #{d} AND l.child_agent_id = #{k})
           OR (l.parent_agent_id = #{k} AND l.child_agent_id = #{d})
           OR (l.parent_agent_id = #{d} AND EXISTS (SELECT 1 FROM ai_agent_lineages o
                 WHERE o.parent_agent_id = #{k} AND o.child_agent_id = l.child_agent_id))
           OR (l.child_agent_id = #{d} AND EXISTS (SELECT 1 FROM ai_agent_lineages o
                 WHERE o.child_agent_id = #{k} AND o.parent_agent_id = l.parent_agent_id))
      SQL
      MERGE_LINEAGE_FKS.each do |table, col|
        connection.exec_update("UPDATE #{table} SET #{col} = $1 WHERE #{col} = $2",
                               "merge-#{table}-#{col}", [ keeper.id, dup.id ])
      end
    end
    private_class_method :merge_lineages!

    # AgentManagedMemoryService reads an agent's private pool with `.first`, so
    # two active private pools after a merge would hide one of them. When the
    # keeper already has one, the duplicate's entries are folded into it
    # (keeper's keys win on conflict) and the duplicate's pool is expired, not
    # deleted, so it stays recoverable. Otherwise the generic owner_agent_id
    # repoint hands the duplicate's pools over unchanged.
    def self.merge_private_memory_pool!(dup, keeper)
      keeper_pool = Ai::MemoryPool.agent_private.for_agent(keeper.id).active.order(:created_at, :id).first
      return unless keeper_pool

      Ai::MemoryPool.agent_private.for_agent(dup.id).active.find_each do |pool|
        keeper_pool.update!(data: pool.data.deep_merge(keeper_pool.data))
        pool.update!(
          owner_agent_id: keeper.id, expires_at: Time.current,
          metadata: (pool.metadata || {}).merge("merged_into_pool_id" => keeper_pool.id, "merged_from_agent_id" => dup.id)
        )
      end
    end
    private_class_method :merge_private_memory_pool!

    private

    attr_reader :account, :user, :doorkeeper_token, :client_info

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

    # The user's identity for this client, regardless of how many sessions
    # hold it. Matches on the client name (stable across re-registrations) or
    # the exact OAuth application (stable across a client rename). Archived
    # agents count too: the daily auth cleanup archives identities with no
    # live session, and the returning client should get its identity back.
    def find_existing_agent
      candidates = self.class.identity_candidates(account.ai_agents)
        .where(creator_id: user&.id)
        .where(
          "mcp_metadata->>'oauth_application_name' = :name OR mcp_metadata->>'oauth_application_id' = :app_id",
          name: client_name, app_id: oauth_application_id.to_s
        )
      agent = self.class.canonical_order(candidates).first
      return agent unless agent&.status == "archived"

      seat_team_ids = Array(agent.mcp_metadata&.dig(ARCHIVED_SEATS_KEY))
      agent.update!(status: "active", mcp_metadata: (agent.mcp_metadata || {}).except(ARCHIVED_SEATS_KEY))
      restore_archived_seats(agent, seat_team_ids)
      restore_workspace_memberships(agent)
      Rails.logger.info "[McpClientIdentityService] Reactivated archived MCP client agent: #{agent.name} (#{agent.id})"
      agent
    end

    def client_name
      oauth_application&.name || "MCP Client"
    end

    def oauth_application_id
      doorkeeper_token.application_id
    end

    def oauth_application
      @oauth_application ||= doorkeeper_token.application
    end

    def create_mcp_agent
      app_name = client_name
      sequence = next_sequence_number(app_name)
      agent_name = "#{app_name} ##{sequence}"

      provider = detect_provider
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

    # Gives a revived agent back the workspace seats archive_agent! recorded.
    def restore_archived_seats(agent, team_ids)
      return if team_ids.empty?

      Ai::AgentTeam.where(account: account, team_type: "workspace", id: team_ids).find_each do |team|
        next if team.members.exists?(ai_agent_id: agent.id)

        team.add_member(agent: agent, role: "executor")
      end
    rescue StandardError => e
      Rails.logger.warn "[McpClientIdentityService] Failed to restore archived workspace seats: #{e.message}"
    end

    # When an MCP agent is created or revived, also join it to workspace teams
    # that have no active mcp_client agent.
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

    # Detects the AI provider from client_info signals and OAuth app name.
    # Builds a keyword string from all available signals, matches against known
    # provider types, then falls back to the first active provider.
    PROVIDER_KEYWORDS = {
      "anthropic" => %w[anthropic claude],
      "openai"    => %w[openai gpt chatgpt],
      "google"    => %w[google gemini],
      "grok"      => %w[grok x.ai xai],
      "ollama"    => %w[ollama],
    }.freeze

    def detect_provider
      signals = client_info.values_at("name", "title", "description", "websiteUrl")
      signals << (oauth_application&.name || "")
      haystack = signals.compact.join(" ").downcase

      PROVIDER_KEYWORDS.each do |provider_type, keywords|
        if keywords.any? { |kw| haystack.include?(kw) }
          match = account.ai_providers.where(is_active: true, provider_type: provider_type).first
          return match if match
        end
      end

      account.ai_providers.where(is_active: true).order(:created_at).first
    end

    def next_sequence_number(app_name)
      # Find the lowest available sequence number across ALL agents (any status).
      # Must check all statuses because name uniqueness is enforced account-wide.
      # MCP client agents persist across sessions (archived, never destroyed,
      # when idle) and are reused via find_existing_agent, so their numbers stay
      # occupied. Only an explicit destroy (mcp:clear_sessions, a confirmed
      # mcp:dedupe_client_agents merge, admin delete) frees a slot.
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

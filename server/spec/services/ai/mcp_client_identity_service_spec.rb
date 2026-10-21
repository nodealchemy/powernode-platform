# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::McpClientIdentityService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:provider) { create(:ai_provider, account: account, is_active: true) }
  let(:oauth_app) { create(:oauth_application, :mcp_client, name: "Claude Code") }
  let(:doorkeeper_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id)
  end

  subject(:service) do
    described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
  end

  # ===========================================================================
  # resolve_agent — reuses orphaned agents, creates new ones for concurrent sessions
  # ===========================================================================
  describe "#resolve_agent" do
    it "creates a new mcp_client agent" do
      agent = service.resolve_agent

      expect(agent).to be_a(Ai::Agent)
      expect(agent).to be_persisted
      expect(agent.agent_type).to eq("mcp_client")
      expect(agent.status).to eq("active")
      expect(agent.account).to eq(account)
      expect(agent.creator).to eq(user)
    end

    it "names the agent with the OAuth app name and sequence number" do
      agent = service.resolve_agent
      expect(agent.name).to eq("Claude Code #1")
    end

    it "caches the result across multiple calls" do
      first = service.resolve_agent
      second = service.resolve_agent
      expect(first).to equal(second)
    end

    it "reuses an orphaned agent with no active session" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      # No active session linked — agent is orphaned and should be reused
      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    # Finding #25: occupancy used to force a fresh "#N" agent per live session,
    # so a client that never DELETEs minted one agent per initialize. Concurrent
    # sessions now share the one identity for (client name, user).
    it "reuses the same agent while another session is active" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
      expect(second_agent.name).to eq("Claude Code #1")
    end

    it "keeps one agent across many initialize-per-call sessions that never close" do
      agents = Array.new(13) do
        svc = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
        session = McpSession.create!(user: user, account: account, status: "active", expires_at: 24.hours.from_now)
        svc.resolve_agent { |a| session.link_agent!(a) }
      end

      expect(agents.map(&:id).uniq.size).to eq(1)
      expect(account.ai_agents.where(agent_type: "mcp_client").count).to eq(1)
      expect(McpSession.active.where(ai_agent_id: agents.first.id).count).to eq(13)
    end

    it "reuses the agent across OAuth applications registered under the same client name" do
      first_agent = service.resolve_agent

      # Dynamic client registration mints a new OAuth application per registration.
      re_registered = create(:oauth_application, :mcp_client, name: "Claude Code")
      re_token = create(:oauth_access_token, oauth_app: re_registered, resource_owner_id: user.id)
      second_agent = described_class.new(account: account, user: user, doorkeeper_token: re_token).resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    it "does not share an agent between users of the same client" do
      first_agent = service.resolve_agent

      other_user = create(:user, account: account)
      other_token = create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: other_user.id)
      other_agent = described_class.new(account: account, user: other_user, doorkeeper_token: other_token).resolve_agent

      expect(other_agent.id).not_to eq(first_agent.id)
      expect(other_agent.creator).to eq(other_user)
      expect(other_agent.name).to eq("Claude Code #2")
    end

    it "reactivates an archived agent for the same client instead of minting a new one" do
      first_agent = service.resolve_agent
      # The daily auth cleanup archives MCP agents with no live session.
      first_agent.update!(status: "archived")

      second_agent = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token).resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
      expect(second_agent.reload.status).to eq("active")
      expect(account.ai_agents.where(agent_type: "mcp_client").count).to eq(1)
    end

    it "gets its workspace seat back after a nightly archive, even when another MCP client sits there" do
      agent = service.resolve_agent
      workspace = create(:ai_agent_team, :workspace, account: account)
      workspace.add_member(agent: agent, role: "executor")
      other_client = create(:ai_agent, :mcp_client, account: account, name: "Cursor #1")
      workspace.add_member(agent: other_client, role: "executor")
      McpSession.create!(user: user, account: account, ai_agent_id: other_client.id)

      McpSession.cleanup_orphaned_agents!
      expect(agent.reload.status).to eq("archived")
      expect(workspace.members.where(ai_agent_id: agent.id)).not_to exist

      revived = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token).resolve_agent

      expect(revived.id).to eq(agent.id)
      expect(workspace.members.where(ai_agent_id: agent.id)).to exist
    end

    it "picks the lowest-numbered active agent when legacy duplicates exist" do
      metadata = { "oauth_application_id" => oauth_app.id, "oauth_application_name" => "Claude Code",
                   "created_by_user_id" => user.id }
      third = create(:ai_agent, :mcp_client, account: account, creator: user, provider: provider,
                                             name: "Claude Code #3", mcp_metadata: metadata)
      first = create(:ai_agent, :mcp_client, account: account, creator: user, provider: provider,
                                             name: "Claude Code #1", mcp_metadata: metadata)
      first.update_columns(created_at: 1.minute.from_now) # creation order must not decide

      expect(service.resolve_agent.id).to eq(first.id)
      expect(third.reload.status).to eq("active")
    end

    it "reuses an agent whose session was revoked past grace period" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      session = McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )
      session.update!(status: "revoked", revoked_at: Time.current)
      # Move revoked_at past the grace period so agent is truly orphaned
      session.update_columns(revoked_at: 11.minutes.ago)

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    it "reuses an agent whose session is revoked but within grace period" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      session = McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )
      session.update!(status: "revoked", revoked_at: Time.current)

      # The reconnecting client gets its identity back whether or not the
      # revoked session is reactivated; no "#2" is minted meanwhile.
      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    it "reuses an agent whose session expired" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 1.minute.ago
      )

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    it "reuses persistent agent after session expires (same identity)" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent
      session = McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )

      # Session expires — agent persists and becomes orphaned (reusable)
      session.update!(status: "expired")

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.name).to eq("Claude Code #1")
      expect(second_agent.id).to eq(first_agent.id)
    end

    it "stores mcp_metadata with OAuth application info" do
      agent = service.resolve_agent

      expect(agent.mcp_metadata).to include(
        "oauth_application_id" => oauth_app.id,
        "oauth_application_name" => "Claude Code",
        "created_by_user_id" => user.id
      )
    end

    it "returns nil when no active provider exists" do
      provider.update!(is_active: false)
      expect(service.resolve_agent).to be_nil
    end

    context "with active workspace teams" do
      let!(:workspace_team) do
        create(:ai_agent_team, :workspace, account: account, status: "active")
      end

      it "auto-joins the agent to workspace teams that lack an mcp_client" do
        agent = service.resolve_agent

        membership = workspace_team.members.find_by(ai_agent_id: agent.id)
        expect(membership).to be_present
        expect(membership.role).to eq("executor")
      end

      it "does not duplicate membership if workspace already has an active mcp_client" do
        existing_mcp = create(:ai_agent, :mcp_client, account: account, status: "active")
        workspace_team.add_member(agent: existing_mcp, role: "executor")

        agent = service.resolve_agent

        expect(workspace_team.members.where(ai_agent_id: agent.id)).not_to exist
      end
    end
  end

  # ===========================================================================
  # deactivate_agent — soft deactivation (no-op), agent persists
  # ===========================================================================
  describe ".deactivate_agent" do
    let(:agent) { create(:ai_agent, :mcp_client, account: account) }
    let(:mcp_session) do
      McpSession.create!(user: user, account: account, ai_agent_id: agent.id)
    end

    it "does NOT destroy the MCP client agent" do
      described_class.deactivate_agent(mcp_session)
      expect(agent.reload).to be_active
    end

    it "preserves agent reference on conversations" do
      conversation = create(:ai_conversation, account: account, agent: agent)
      described_class.deactivate_agent(mcp_session)
      expect(conversation.reload.ai_agent_id).to eq(agent.id)
    end

    it "preserves agent reference on messages" do
      conversation = create(:ai_conversation, account: account, agent: agent)
      message = create(:ai_message, conversation: conversation, agent: agent, role: "assistant")
      described_class.deactivate_agent(mcp_session)
      expect(message.reload.ai_agent_id).to eq(agent.id)
    end

    it "preserves agent reference on MCP sessions" do
      described_class.deactivate_agent(mcp_session)
      expect(mcp_session.reload.ai_agent_id).to eq(agent.id)
    end

    it "preserves workspace team memberships" do
      workspace_team = create(:ai_agent_team, :workspace, account: account)
      create(:ai_agent_team_member, team: workspace_team, agent: agent, role: "executor")

      described_class.deactivate_agent(mcp_session)
      expect(workspace_team.members.where(ai_agent_id: agent.id)).to exist
    end

    it "skips non-mcp_client agents" do
      regular_agent = create(:ai_agent, account: account, agent_type: "assistant")
      session = McpSession.create!(user: user, account: account, ai_agent_id: regular_agent.id)

      described_class.deactivate_agent(session)
      expect(regular_agent.reload.status).to eq("active")
    end

    it "skips already-archived agents" do
      agent.update!(status: "archived")

      expect { described_class.deactivate_agent(mcp_session) }
        .not_to(change { Ai::Agent.where(id: agent.id).count })
    end

    it "skips sessions without an agent" do
      orphan_session = McpSession.create!(user: user, account: account)
      expect { described_class.deactivate_agent(orphan_session) }.not_to raise_error
    end
  end

  # ===========================================================================
  # force_deactivate_agent — destroys agent, nullifies FKs, removes memberships
  # ===========================================================================
  describe ".force_deactivate_agent" do
    let(:agent) { create(:ai_agent, :mcp_client, account: account) }
    let(:mcp_session) do
      McpSession.create!(user: user, account: account, ai_agent_id: agent.id)
    end

    it "destroys the MCP client agent" do
      agent_id = agent.id
      described_class.force_deactivate_agent(mcp_session)
      expect(Ai::Agent.find_by(id: agent_id)).to be_nil
    end

    it "nullifies agent reference on conversations" do
      conversation = create(:ai_conversation, account: account, agent: agent)
      described_class.force_deactivate_agent(mcp_session)
      expect(conversation.reload.ai_agent_id).to be_nil
    end

    it "nullifies agent reference on messages" do
      conversation = create(:ai_conversation, account: account, agent: agent)
      message = create(:ai_message, conversation: conversation, agent: agent, role: "assistant")
      described_class.force_deactivate_agent(mcp_session)
      expect(message.reload.ai_agent_id).to be_nil
    end

    it "nullifies agent reference on MCP sessions" do
      described_class.force_deactivate_agent(mcp_session)
      expect(mcp_session.reload.ai_agent_id).to be_nil
    end

    it "removes the agent from workspace teams" do
      workspace_team = create(:ai_agent_team, :workspace, account: account)
      create(:ai_agent_team_member, team: workspace_team, agent: agent, role: "executor")

      described_class.force_deactivate_agent(mcp_session)
      expect(workspace_team.members.where(ai_agent_id: agent.id)).not_to exist
    end

    it "removes all team memberships when destroying agent" do
      regular_team = create(:ai_agent_team, account: account)
      membership = build(:ai_agent_team_member, team: regular_team, agent: agent)
      membership.save!(validate: false)

      described_class.force_deactivate_agent(mcp_session)
      expect(Ai::AgentTeamMember.find_by(id: membership.id)).to be_nil
    end

    it "works on archived agents too" do
      agent.update!(status: "archived")
      agent_id = agent.id

      described_class.force_deactivate_agent(mcp_session)
      expect(Ai::Agent.find_by(id: agent_id)).to be_nil
    end

    it "skips non-mcp_client agents" do
      regular_agent = create(:ai_agent, account: account, agent_type: "assistant")
      session = McpSession.create!(user: user, account: account, ai_agent_id: regular_agent.id)

      described_class.force_deactivate_agent(session)
      expect(regular_agent.reload).to be_persisted
    end

    it "skips sessions without an agent" do
      orphan_session = McpSession.create!(user: user, account: account)
      expect { described_class.force_deactivate_agent(orphan_session) }.not_to raise_error
    end
  end

  # ===========================================================================
  # Sequence numbering
  # ===========================================================================
  describe "sequence numbering" do
    it "starts at 1 for a fresh account" do
      agent = service.resolve_agent
      expect(agent.name).to eq("Claude Code #1")
    end

    it "handles different OAuth app names independently" do
      service.resolve_agent # Claude Code #1

      other_app = create(:oauth_application, :mcp_client, name: "Cursor")
      other_token = create(:oauth_access_token, oauth_app: other_app, resource_owner_id: user.id)
      other_service = described_class.new(account: account, user: user, doorkeeper_token: other_token)

      agent = other_service.resolve_agent
      expect(agent.name).to eq("Cursor #1")
    end

    it "never numbers past #1 for concurrent instances of one client and user" do
      agents = (1..3).map do |_|
        svc = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
        agent = svc.resolve_agent
        McpSession.create!(
          user: user, account: account, ai_agent_id: agent.id,
          status: "active", expires_at: 24.hours.from_now
        )
        agent
      end

      expect(agents.map(&:name)).to eq([ "Claude Code #1" ] * 3)
    end

    it "fills the lowest free number when a new identity is needed" do
      create(:ai_agent, :mcp_client, account: account, name: "Claude Code #1") # another user's identity
      create(:ai_agent, :mcp_client, account: account, name: "Claude Code #3")

      expect(service.resolve_agent.name).to eq("Claude Code #2")
    end
  end

  # ===========================================================================
  # Advisory lock — serializes concurrent resolve_agent calls
  # ===========================================================================
  describe "advisory locking" do
    it "uses pg_advisory_xact_lock during resolve_agent" do
      expect(ActiveRecord::Base.connection).to receive(:execute)
        .with(/pg_advisory_xact_lock/)
        .and_call_original

      service.resolve_agent
    end

    it "yields the agent to a block inside the lock" do
      yielded_agent = nil
      agent = service.resolve_agent { |a| yielded_agent = a }

      expect(yielded_agent).to eq(agent)
      expect(yielded_agent).to be_persisted
    end

    it "links agent to session atomically via block" do
      session = McpSession.create!(
        user: user, account: account,
        status: "active", expires_at: 24.hours.from_now
      )

      agent = service.resolve_agent { |a| session.link_agent!(a) }

      session.reload
      expect(session.ai_agent_id).to eq(agent.id)
      expect(session.display_name).to eq(agent.name)
    end
  end

  # ===========================================================================
  # Duplicate identities — report, and merge only on explicit confirm
  # ===========================================================================
  describe "duplicate agent cleanup" do
    let(:metadata) do
      { "oauth_application_id" => oauth_app.id, "oauth_application_name" => "Claude Code",
        "created_by_user_id" => user.id }
    end

    def legacy_agent(number, **attrs)
      create(:ai_agent, :mcp_client, account: account, creator: user, provider: provider,
                                     name: "Claude Code ##{number}", mcp_metadata: metadata, **attrs)
    end

    let!(:keeper) { legacy_agent(1) }
    let!(:duplicates) { (2..6).map { |n| legacy_agent(n) } }

    describe ".duplicate_agents_report" do
      it "reports count, the first 3 and the last 1 duplicates without deleting anything" do
        report = described_class.duplicate_agents_report(account: account)

        expect(report[:count]).to eq(5)
        expect(report[:first].map { |d| d[:name] }).to eq([ "Claude Code #2", "Claude Code #3", "Claude Code #4" ])
        expect(report[:last][:name]).to eq("Claude Code #6")
        expect(report[:groups].first).to include(client_name: "Claude Code", user_id: user.id)
        expect(report[:groups].first[:keeper]).to include(id: keeper.id, name: "Claude Code #1")
        expect(Ai::Agent.where(id: duplicates.map(&:id)).count).to eq(5)
      end

      it "counts, per duplicate, every row a merge would drop" do
        dup = duplicates.first
        create(:ai_agent_short_term_memory, agent: dup, account: account)
        create(:ai_agent_skill, agent: dup)
        create(:ai_agent_budget, agent: dup, account: account)
        create(:ai_agent_trust_score, agent: dup, account: account)
        create(:ai_guardrail_config, account: account, agent: dup)

        report = described_class.duplicate_agents_report(account: account)
        dropped = report[:groups].first[:duplicates].find { |d| d[:id] == dup.id }[:drops]

        # Keyed "table.column"; only non-zero counts are listed.
        expect(dropped).to eq(
          "ai_agent_short_term_memories.agent_id" => 1, "ai_agent_skills.ai_agent_id" => 1,
          "ai_agent_budgets.agent_id" => 1, "ai_agent_trust_scores.agent_id" => 1,
          "ai_guardrail_configs.ai_agent_id" => 1
        )
        expect(report[:first].first[:drops]).to eq(dropped)
      end

      it "does not count a duplicate's deferred operations as drops: a merge keeps them" do
        dup = duplicates.first
        Ai::DeferredOperation.create!(account: account, ai_agent: dup, action_category: "release.promote",
                                      executor_class: "TestSpecExecutor", params: { foo: "bar" },
                                      status: "completed", executed_at: Time.current)
        create(:ai_guardrail_config, account: account, agent: dup)

        report = described_class.duplicate_agents_report(account: account)
        dropped = report[:groups].first[:duplicates].find { |d| d[:id] == dup.id }[:drops]

        # The guardrail config proves drops are being counted for this duplicate.
        expect(dropped).to eq("ai_guardrail_configs.ai_agent_id" => 1)
      end

      it "skips a duplicate holding a live deferred operation, which could no longer replay as its requester" do
        dup = duplicates.first
        Ai::DeferredOperation.create!(account: account, ai_agent: dup, action_category: "release.promote",
                                      executor_class: "TestSpecExecutor", params: { foo: "bar" })

        report = described_class.duplicate_agents_report(account: account)

        expect(report[:count]).to eq(4)
        expect(report[:skipped]).to contain_exactly(include(id: dup.id, reason: "unsettled_operations"))
      end

      it "groups by user, so one identity per user is not a duplicate" do
        other_user = create(:user, account: account)
        create(:ai_agent, :mcp_client, account: account, creator: other_user, provider: provider,
                                       name: "Claude Code #7",
                                       mcp_metadata: metadata.merge("created_by_user_id" => other_user.id))

        report = described_class.duplicate_agents_report(account: account)

        expect(report[:count]).to eq(5)
        expect(report[:groups].size).to eq(1)
      end

      it "lists a duplicate with a live session as skipped, not removable" do
        McpSession.create!(user: user, account: account, ai_agent_id: duplicates.last.id,
                           status: "active", expires_at: 24.hours.from_now)

        report = described_class.duplicate_agents_report(account: account)

        expect(report[:count]).to eq(4)
        expect(report[:skipped]).to contain_exactly(include(id: duplicates.last.id, reason: "live_session"))
      end

      it "lists a duplicate in a manually configured team as skipped" do
        team = create(:ai_agent_team, account: account)
        build(:ai_agent_team_member, team: team, agent: duplicates.first).save!(validate: false)

        report = described_class.duplicate_agents_report(account: account)

        expect(report[:skipped]).to contain_exactly(include(id: duplicates.first.id, reason: "manual_team"))
      end
    end

    describe ".merge_duplicate_agents!" do
      it "changes nothing without confirm" do
        result = described_class.merge_duplicate_agents!(confirm: false, account: account)

        expect(result[:dry_run]).to be(true)
        expect(result[:merged]).to eq(0)
        expect(Ai::Agent.where(id: duplicates.map(&:id)).count).to eq(5)
      end

      it "merges duplicates into the keeper on confirm, keeping their attribution" do
        dup = duplicates.first
        execution = create(:ai_agent_execution, account: account, agent: dup, user: user, provider: provider)
        conversation = create(:ai_conversation, account: account, agent: dup)
        message = create(:ai_message, conversation: conversation, agent: dup, role: "assistant")
        expired = McpSession.create!(user: user, account: account, ai_agent_id: dup.id, status: "expired")

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:dry_run]).to be(false)
        expect(result[:merged]).to eq(5)
        expect(Ai::Agent.where(id: duplicates.map(&:id))).to be_empty
        expect(keeper.reload).to be_active
        expect(execution.reload.ai_agent_id).to eq(keeper.id)
        expect(conversation.reload.ai_agent_id).to eq(keeper.id)
        expect(message.reload.ai_agent_id).to eq(keeper.id)
        expect(expired.reload).to have_attributes(ai_agent_id: keeper.id, display_name: keeper.name)
      end

      it "keeps a duplicate's executed deferred operations, repointed to the keeper, as the record of what ran" do
        dup = duplicates.first
        operation = Ai::DeferredOperation.create!(account: account, ai_agent: dup, action_category: "release.promote",
                                                  executor_class: "TestSpecExecutor", params: { foo: "bar" },
                                                  status: "completed", executed_at: Time.current)

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:errors]).to be_empty
        expect(operation.reload.ai_agent_id).to eq(keeper.id)
      end

      it "leaves a duplicate with a live deferred operation, and that operation, untouched" do
        dup = duplicates.first
        operation = Ai::DeferredOperation.create!(account: account, ai_agent: dup, action_category: "release.promote",
                                                  executor_class: "TestSpecExecutor", params: { foo: "bar" })

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:merged]).to eq(4)
        expect(Ai::Agent.where(id: dup.id)).to exist
        expect(operation.reload).to have_attributes(ai_agent_id: dup.id, status: "pending")
      end

      it "re-checks inside the merge: an operation parked after the report leaves that duplicate unmerged" do
        dup = duplicates.first
        clean_report = described_class.duplicate_agents_report(account: account)
        allow(described_class).to receive(:duplicate_agents_report).and_return(clean_report)
        operation = Ai::DeferredOperation.create!(account: account, ai_agent: dup, action_category: "release.promote",
                                                  executor_class: "TestSpecExecutor", params: { foo: "bar" })

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:merged]).to eq(4)
        expect(result[:errors]).to contain_exactly(include(id: dup.id, error: include("unsettled_operations")))
        expect(Ai::Agent.where(id: dup.id)).to exist
        expect(operation.reload.ai_agent_id).to eq(dup.id)
      end

      it "repoints every history table's rows to the keeper instead of deleting them" do
        dup = duplicates.first
        connection = ActiveRecord::Base.connection
        team = create(:ai_agent_team, account: account)
        goal_id = SecureRandom.uuid
        connection.exec_insert(<<~SQL.squish, "goal", [ goal_id, account.id, dup.id ])
          INSERT INTO ai_agent_goals (id, account_id, ai_agent_id, goal_type, title, created_at, updated_at)
          VALUES ($1, $2, $3, 'maintenance', 'g', NOW(), NOW())
        SQL
        # Each table's NOT NULL columns beyond id/account/agent/timestamps. Raw
        # inserts: none of these models has a factory.
        required = {
          "ai_agent_proposals" => { "proposal_type" => "feature", "title" => "t" },
          "ai_agent_escalations" => { "escalation_type" => "stuck", "title" => "t" },
          "ai_agent_feedbacks" => { "feedback_type" => "thumbs", "rating" => 5, "user_id" => user.id },
          "ai_goal_plans" => { "goal_id" => goal_id },
          "ai_agent_observations" => { "observation_type" => "anomaly", "sensor_type" => "k", "title" => "t" },
          "ai_team_restructure_events" => { "ai_agent_team_id" => team.id, "event_type" => "added" }
        }
        ids = required.to_h do |table, extra|
          id = SecureRandom.uuid
          columns = [ "id", "account_id", "ai_agent_id", *extra.keys ]
          values = [ id, account.id, dup.id, *extra.values ]
          placeholders = values.each_index.map { |i| "$#{i + 1}" }
          connection.exec_insert(
            "INSERT INTO #{table} (#{columns.join(', ')}, created_at, updated_at) " \
            "VALUES (#{placeholders.join(', ')}, NOW(), NOW())",
            "history-#{table}", values
          )
          [ table, id ]
        end
        expect(ids.keys + [ "ai_deferred_operations" ]).to match_array(described_class::MERGE_HISTORY_FKS.map(&:first))

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:errors]).to be_empty
        ids.each do |table, id|
          agent = connection.select_value("SELECT ai_agent_id FROM #{table} WHERE id = #{connection.quote(id)}")
          expect(agent).to eq(keeper.id), "#{table} row was #{agent.nil? ? 'deleted or nulled' : "left on #{agent}"}"
        end
      end

      it "rolls back a failed merge, reports it, and leaves the keeper intact" do
        dup = duplicates.first
        execution = create(:ai_agent_execution, account: account, agent: dup, user: user, provider: provider)
        allow_any_instance_of(Ai::Agent).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, "blocked")

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:merged]).to eq(0)
        expect(result[:errors].map { |e| e[:id] }).to match_array(duplicates.map(&:id))
        expect(result[:errors].first[:error]).to include("blocked")
        expect(keeper.reload).to be_active
        expect(Ai::Agent.where(id: duplicates.map(&:id)).count).to eq(5)
        expect(execution.reload.ai_agent_id).to eq(dup.id)
      end

      it "hands a duplicate's memory pools to the keeper when the keeper has none" do
        pool = create(:ai_memory_pool, account: account, pool_type: "agent_private", owner_agent_id: duplicates.first.id,
                                       data: { "note" => "from dup" })

        described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(pool.reload.owner_agent_id).to eq(keeper.id)
        expect(Ai::MemoryPool.agent_private.for_agent(keeper.id).active.first).to eq(pool)
      end

      it "folds a duplicate's private pool into the keeper's own (keeper keys win) and retires it" do
        keeper_pool = create(:ai_memory_pool, account: account, pool_type: "agent_private", owner_agent_id: keeper.id,
                                              data: { "shared" => "keeper", "mine" => 1 })
        dup_pool = create(:ai_memory_pool, account: account, pool_type: "agent_private",
                                           owner_agent_id: duplicates.first.id,
                                           data: { "shared" => "dup", "theirs" => 2 })

        described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(keeper_pool.reload.data).to eq("shared" => "keeper", "mine" => 1, "theirs" => 2)
        expect(dup_pool.reload).to have_attributes(owner_agent_id: keeper.id)
        expect(dup_pool).to be_expired
        expect(Ai::MemoryPool.agent_private.for_agent(keeper.id).active).to contain_exactly(keeper_pool)
      end

      it "repoints the duplicate's work history to the keeper" do
        dup = duplicates.first
        shadow = create(:ai_shadow_execution, account: account, agent: dup)
        evaluation = create(:ai_evaluation_result, account: account, agent: dup)
        worktree = create(:ai_worktree, account: account, ai_agent: dup)
        role = create(:ai_team_role, account: account, ai_agent: dup)

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:errors]).to be_empty
        expect(shadow.reload.agent_id).to eq(keeper.id)
        expect(evaluation.reload.agent_id).to eq(keeper.id)
        expect(worktree.reload.ai_agent_id).to eq(keeper.id)
        expect(role.reload.ai_agent_id).to eq(keeper.id)
      end

      it "collapses lineages onto the keeper without self-lineage or duplicate pairs" do
        dup = duplicates.first
        other = create(:ai_agent, account: account)
        sibling = create(:ai_agent, account: account)
        create(:ai_agent_lineage, account: account, parent_agent: keeper, child_agent: dup)   # becomes self
        create(:ai_agent_lineage, account: account, parent_agent: keeper, child_agent: other) # already there
        create(:ai_agent_lineage, account: account, parent_agent: dup, child_agent: other)    # would duplicate
        moved = create(:ai_agent_lineage, account: account, parent_agent: dup, child_agent: sibling)

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:errors]).to be_empty
        pairs = Ai::AgentLineage.where(parent_agent_id: keeper.id).pluck(:child_agent_id)
        expect(pairs).to contain_exactly(other.id, sibling.id)
        expect(moved.reload.parent_agent_id).to eq(keeper.id)
        expect(Ai::AgentLineage.where("parent_agent_id = child_agent_id")).to be_empty
      end

      it "moves workspace memberships to the keeper without duplicating them" do
        shared = create(:ai_agent_team, :workspace, account: account)
        shared.add_member(agent: keeper, role: "executor")
        shared.add_member(agent: duplicates.first, role: "executor")
        only_dup = create(:ai_agent_team, :workspace, account: account)
        only_dup.add_member(agent: duplicates.second, role: "executor")

        described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(shared.members.where(ai_agent_id: keeper.id).count).to eq(1)
        expect(only_dup.members.where(ai_agent_id: keeper.id)).to exist
      end

      it "leaves skipped duplicates in place" do
        live = duplicates.last
        McpSession.create!(user: user, account: account, ai_agent_id: live.id,
                           status: "active", expires_at: 24.hours.from_now)

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:merged]).to eq(4)
        expect(live.reload).to be_persisted
      end

      it "treats a duplicate whose session has gone idle as orphaned" do
        idle = duplicates.last
        session = McpSession.create!(user: user, account: account, ai_agent_id: idle.id,
                                     status: "active", expires_at: 24.hours.from_now)
        session.update_columns(last_activity_at: (McpSession.idle_timeout + 1.minute).ago)

        result = described_class.merge_duplicate_agents!(confirm: true, account: account)

        expect(result[:merged]).to eq(5)
        expect(session.reload.ai_agent_id).to eq(keeper.id)
      end
    end
  end

  # ===========================================================================
  # Every FK to ai_agents must have a merge rule (review: silent cascades/RESTRICTs)
  # ===========================================================================
  describe "merge foreign-key coverage" do
    it "classifies every foreign key that references ai_agents" do
      connection = ActiveRecord::Base.connection
      db_fks = connection.tables.flat_map do |table|
        connection.foreign_keys(table).select { |fk| fk.to_table == "ai_agents" }.map { |fk| [ table, fk.column ] }
      end

      expect(db_fks).not_to be_empty
      unclassified = db_fks.uniq - described_class.classified_agent_fks
      expect(unclassified).to be_empty,
                              "FKs to ai_agents with no merge rule (repoint, delete or drop): #{unclassified.inspect}"
    end

    it "gives every foreign key exactly one merge rule" do
      classified = described_class.classified_agent_fks
      expect(classified.tally.select { |_, n| n > 1 }.keys).to be_empty
      expect(described_class::MERGE_HISTORY_FKS - Ai::Tools::AgentManagementTool::DELETE_AGENT_ROWS).to be_empty
    end
  end
end

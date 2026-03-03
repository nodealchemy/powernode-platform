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

    it "creates a new agent when existing one is linked to an active session" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      # Simulate an active session bound to the first agent
      McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).not_to eq(first_agent.id)
      expect(second_agent.name).to eq("Claude Code #2")
    end

    it "reuses an agent whose only active session is auto-provisioned" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      # Simulate an auto-provisioned session (created by session/discover self-healing)
      McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now,
        client_info: { "name" => "Claude Code", "version" => "auto-provisioned" }
      )

      # A real client should reuse the same agent, not create a new one
      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
      expect(second_agent.name).to eq("Claude Code #1")
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

    it "does not reuse an agent whose session is revoked but within grace period" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      session = McpSession.create!(
        user: user, account: account, ai_agent_id: first_agent.id,
        status: "active", expires_at: 24.hours.from_now
      )
      session.update!(status: "revoked", revoked_at: Time.current)

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).not_to eq(first_agent.id)
      expect(second_agent.name).to eq("Claude Code #2")
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

    it "assigns sequential numbers to concurrent instances" do
      agents = (1..3).map do |_|
        svc = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
        agent = svc.resolve_agent
        # Bind each agent to an active session so the next iteration sees it as claimed
        McpSession.create!(
          user: user, account: account, ai_agent_id: agent.id,
          status: "active", expires_at: 24.hours.from_now
        )
        agent
      end

      expect(agents.map(&:name)).to eq(["Claude Code #1", "Claude Code #2", "Claude Code #3"])
    end

    it "recycles a lower-numbered agent after its session ends past grace period" do
      # Create agents #1 and #2 with active sessions
      agents = (1..2).map do |_|
        svc = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
        agent = svc.resolve_agent
        McpSession.create!(
          user: user, account: account, ai_agent_id: agent.id,
          status: "active", expires_at: 24.hours.from_now
        )
        agent
      end

      # Revoke session for agent #1 and move past grace period
      session = McpSession.where(ai_agent_id: agents[0].id).first
      session.revoke!
      session.update_columns(revoked_at: 11.minutes.ago)

      # Next resolve should reuse agent #1 (orphaned past grace), not create #3
      svc = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      recycled = svc.resolve_agent

      expect(recycled.id).to eq(agents[0].id)
      expect(recycled.name).to eq("Claude Code #1")
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
end

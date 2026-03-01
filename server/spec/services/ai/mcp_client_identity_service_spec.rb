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
  # resolve_agent — always creates a fresh agent, never reuses
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

    it "reuses an existing active agent for the same OAuth application" do
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.id).to eq(first_agent.id)
    end

    it "increments sequence even when prior agents are archived" do
      # Create and archive agent #1
      first_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      first_agent = first_service.resolve_agent
      first_agent.update!(status: "archived")

      second_service = described_class.new(account: account, user: user, doorkeeper_token: doorkeeper_token)
      second_agent = second_service.resolve_agent

      expect(second_agent.name).to eq("Claude Code #2")
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

      it "auto-joins the agent to workspace teams" do
        agent = service.resolve_agent

        expect(workspace_team.members.where(ai_agent_id: agent.id)).to exist
      end

      it "assigns executor role with code capabilities" do
        agent = service.resolve_agent
        member = workspace_team.members.find_by(ai_agent_id: agent.id)

        expect(member.role).to eq("executor")
        expect(member.capabilities).to include("code_execution", "system_commands", "file_operations")
      end

      it "does not join inactive workspace teams" do
        inactive_team = create(:ai_agent_team, :workspace, account: account, status: "inactive")
        agent = service.resolve_agent

        expect(inactive_team.members.where(ai_agent_id: agent.id)).not_to exist
      end

      it "does not join non-workspace teams" do
        regular_team = create(:ai_agent_team, account: account, status: "active")
        agent = service.resolve_agent

        expect(regular_team.members.where(ai_agent_id: agent.id)).not_to exist
      end
    end
  end

  # ===========================================================================
  # deactivate_agent — archives agent and removes from workspace teams
  # ===========================================================================
  describe ".deactivate_agent" do
    let(:agent) { create(:ai_agent, :mcp_client, account: account) }
    let(:mcp_session) do
      McpSession.create!(user: user, account: account, ai_agent_id: agent.id)
    end

    it "archives the MCP client agent" do
      described_class.deactivate_agent(mcp_session)
      expect(agent.reload.status).to eq("archived")
    end

    it "removes the agent from workspace teams" do
      workspace_team = create(:ai_agent_team, :workspace, account: account)
      create(:ai_agent_team_member, team: workspace_team, agent: agent, role: "executor")

      described_class.deactivate_agent(mcp_session)
      expect(workspace_team.members.where(ai_agent_id: agent.id)).not_to exist
    end

    it "does not remove agent from non-workspace teams" do
      regular_team = create(:ai_agent_team, account: account)
      # Bypass validation since restrict_mcp_client_to_workspace_teams prevents
      # this in production — we're testing the removal scope only targets workspace teams
      membership = build(:ai_agent_team_member, team: regular_team, agent: agent)
      membership.save!(validate: false)

      described_class.deactivate_agent(mcp_session)
      expect(Ai::AgentTeamMember.find_by(id: membership.id)).to be_present
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
        .not_to change { agent.reload.status }
    end

    it "skips sessions without an agent" do
      orphan_session = McpSession.create!(user: user, account: account)
      expect { described_class.deactivate_agent(orphan_session) }.not_to raise_error
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
  end
end

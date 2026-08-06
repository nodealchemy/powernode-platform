# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Agent::McpServerIntegration, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user) }

  describe "#mcp_server_ids" do
    it "round-trips through mcp_metadata" do
      server = create(:mcp_server, :connected, account: account)
      agent.mcp_server_ids = [server.id]

      expect(agent.mcp_server_ids).to eq([server.id])
      expect(agent.mcp_metadata["mcp_server_ids"]).to eq([server.id])
    end

    it "defaults to an empty array" do
      expect(agent.mcp_server_ids).to eq([])
    end

    it "compacts nils out of the assigned list" do
      server = create(:mcp_server, :connected, account: account)
      agent.mcp_server_ids = [server.id, nil]

      expect(agent.mcp_server_ids).to eq([server.id])
    end
  end

  describe "#mcp_servers" do
    it "returns only attached, connected servers in this account" do
      connected = create(:mcp_server, :connected, account: account)
      disconnected = create(:mcp_server, account: account) # status: disconnected
      other_account_server = create(:mcp_server, :connected, account: create(:account))

      agent.mcp_server_ids = [connected.id, disconnected.id, other_account_server.id]

      expect(agent.mcp_servers).to contain_exactly(connected)
    end

    it "returns none when nothing is attached" do
      create(:mcp_server, :connected, account: account)
      expect(agent.mcp_servers).to be_empty
    end

    it "returns none for a global (account-less) agent" do
      global_agent = create(:ai_agent, account: nil, creator: user)
      global_agent.mcp_server_ids = [create(:mcp_server, :connected, account: account).id]

      expect(global_agent.mcp_servers).to be_empty
    end
  end

  describe "#available_mcp_tools" do
    it "returns only enabled tools across attached connected servers" do
      server = create(:mcp_server, :connected, account: account)
      enabled_tool = create(:mcp_tool, :enabled, mcp_server: server)
      _disabled_tool = create(:mcp_tool, mcp_server: server, enabled: false)
      agent.mcp_server_ids = [server.id]

      expect(agent.available_mcp_tools).to contain_exactly(enabled_tool)
    end

    it "excludes tools on a disconnected server even if attached" do
      disconnected = create(:mcp_server, account: account)
      create(:mcp_tool, :enabled, mcp_server: disconnected)
      agent.mcp_server_ids = [disconnected.id]

      expect(agent.available_mcp_tools).to be_empty
    end
  end
end

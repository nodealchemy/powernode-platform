# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ConnectionsService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  subject(:service) { described_class.new(agent: agent, account: account) }

  describe '#call' do
    context 'when agent has no connections' do
      it 'returns the agent node with empty edges' do
        result = service.call

        expect(result[:nodes].size).to eq(1)
        expect(result[:nodes].first[:id]).to eq(agent.id)
        expect(result[:nodes].first[:type]).to eq('agent')
        expect(result[:edges]).to be_empty
        expect(result[:summary]).to eq({
          teams: 0,
          peers: 0,
          mcp_servers: 0,
          connections: 0
        })
      end
    end

    context 'when agent has team memberships' do
      let(:team) { create(:ai_agent_team, account: account) }
      let(:peer_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

      before do
        create(:ai_agent_team_member, team: team, agent: agent, role: 'manager', is_lead: true)
        create(:ai_agent_team_member, team: team, agent: peer_agent, role: 'researcher')
      end

      it 'includes team and peer agent nodes' do
        result = service.call

        node_types = result[:nodes].map { |n| n[:type] }
        expect(node_types).to include('agent', 'team', 'peer_agent')

        edge_labels = result[:edges].map { |e| e[:label] }
        expect(edge_labels).to include('leads')
        expect(edge_labels).to include('researcher')

        expect(result[:summary][:teams]).to eq(1)
        expect(result[:summary][:peers]).to eq(1)
      end
    end

    context 'when agent has MCP tool usage connections' do
      before do
        create(:ai_agent_connection,
          account: account,
          source_type: 'Ai::Agent',
          source_id: agent.id,
          target_type: 'Mcp::Server',
          target_id: SecureRandom.uuid,
          connection_type: 'mcp_tool_usage',
          status: 'active',
          metadata: { 'tool_name' => 'code_search' }
        )
      end

      it 'includes MCP server nodes' do
        result = service.call

        node_types = result[:nodes].map { |n| n[:type] }
        expect(node_types).to include('mcp_server')

        expect(result[:summary][:mcp_servers]).to eq(1)
        expect(result[:summary][:connections]).to be >= 1
      end
    end

    context 'when agent has A2A communication connections' do
      let(:peer_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

      before do
        create(:ai_agent_connection,
          account: account,
          source_type: 'Ai::Agent',
          source_id: agent.id,
          target_type: 'Ai::Agent',
          target_id: peer_agent.id,
          connection_type: 'a2a_communication',
          status: 'active'
        )
      end

      it 'includes peer agent from A2A connections' do
        result = service.call

        node_types = result[:nodes].map { |n| n[:type] }
        expect(node_types).to include('peer_agent')

        edge_relationships = result[:edges].map { |e| e[:relationship] }
        expect(edge_relationships).to include('a2a_communication')
      end
    end

    context 'with mixed connections' do
      let(:team) { create(:ai_agent_team, account: account) }
      let(:peer_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

      before do
        create(:ai_agent_team_member, team: team, agent: agent, role: 'manager')
        create(:ai_agent_connection,
          account: account,
          source_type: 'Ai::Agent',
          source_id: agent.id,
          target_type: 'Ai::Agent',
          target_id: peer_agent.id,
          connection_type: 'a2a_communication',
          status: 'active'
        )
      end

      it 'returns correct summary counts' do
        result = service.call

        expect(result[:summary][:teams]).to eq(1)
        expect(result[:summary][:connections]).to be >= 2
      end

      it 'deduplicates nodes' do
        result = service.call
        ids = result[:nodes].map { |n| n[:id] }
        expect(ids).to eq(ids.uniq)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Conversation, type: :model do
  describe '#cleanup_orphaned_workspace_team' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:provider) { create(:ai_provider, account: account) }
    let(:agent) { create(:ai_agent, account: account, provider: provider) }

    context 'when conversation belongs to a workspace team' do
      let(:workspace_team) do
        create(:ai_agent_team, account: account, team_type: 'workspace', coordination_strategy: 'round_robin')
      end

      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: workspace_team,
               conversation_type: 'team')
      end

      it 'destroys the workspace team when the last conversation is deleted' do
        expect { conversation.destroy! }.to change { Ai::AgentTeam.count }.by(-1)
        expect(Ai::AgentTeam.find_by(id: workspace_team.id)).to be_nil
      end

      it 'does not destroy the workspace team when other conversations remain' do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: workspace_team,
               conversation_type: 'team')

        expect { conversation.destroy! }.not_to change { Ai::AgentTeam.count }
      end
    end

    context 'when conversation belongs to a non-workspace team' do
      let(:team) do
        create(:ai_agent_team, account: account, team_type: 'hierarchical', coordination_strategy: 'manager_led')
      end

      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider,
               agent_team: team,
               conversation_type: 'team')
      end

      it 'does not destroy the team' do
        expect { conversation.destroy! }.not_to change { Ai::AgentTeam.count }
      end
    end

    context 'when conversation has no team' do
      let!(:conversation) do
        create(:ai_conversation,
               account: account,
               user: user,
               agent: agent,
               provider: provider)
      end

      it 'does not raise an error' do
        expect { conversation.destroy! }.not_to raise_error
      end
    end
  end
end

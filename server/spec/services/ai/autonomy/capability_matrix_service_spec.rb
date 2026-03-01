# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::CapabilityMatrixService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#check' do
    context 'supervised agent' do
      let!(:trust_score) { create(:ai_agent_trust_score, account: account, agent: agent, tier: 'supervised') }

      it 'allows read_data' do
        expect(service.check(agent: agent, action_type: 'read_data')).to eq(:allowed)
      end

      it 'requires approval for execute_tool' do
        expect(service.check(agent: agent, action_type: 'execute_tool')).to eq(:requires_approval)
      end

      it 'denies spawn_agent' do
        expect(service.check(agent: agent, action_type: 'spawn_agent')).to eq(:denied)
      end

      it 'denies unknown actions' do
        expect(service.check(agent: agent, action_type: 'unknown_action')).to eq(:denied)
      end
    end

    context 'trusted agent' do
      let!(:trust_score) { create(:ai_agent_trust_score, :trusted, account: account, agent: agent) }

      it 'allows spawn_agent' do
        expect(service.check(agent: agent, action_type: 'spawn_agent')).to eq(:allowed)
      end

      it 'requires approval for delete_data' do
        expect(service.check(agent: agent, action_type: 'delete_data')).to eq(:requires_approval)
      end
    end

    context 'agent without trust score' do
      it 'defaults to supervised tier' do
        expect(service.check(agent: agent, action_type: 'spawn_agent')).to eq(:denied)
      end
    end
  end

  describe '#full_matrix' do
    it 'returns the full capability matrix' do
      matrix = service.full_matrix

      expect(matrix).to have_key('supervised')
      expect(matrix).to have_key('monitored')
      expect(matrix).to have_key('trusted')
      expect(matrix).to have_key('autonomous')
      expect(matrix['supervised']).to have_key('read_data')
    end
  end

  describe '#agent_capabilities' do
    let!(:trust_score) { create(:ai_agent_trust_score, :monitored, account: account, agent: agent) }

    it 'returns capabilities for agent tier' do
      result = service.agent_capabilities(agent: agent)

      expect(result[:agent_id]).to eq(agent.id)
      expect(result[:tier]).to eq('monitored')
      expect(result[:capabilities]).to include('read_data' => :allowed)
    end
  end
end

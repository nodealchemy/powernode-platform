# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::DelegationAuthorityService do
  let(:account) { create(:account) }
  let(:delegator) { create(:ai_agent, account: account) }
  let(:delegate_agent) { create(:ai_agent, account: account, agent_type: 'assistant') }
  let(:service) { described_class.new(account: account) }

  describe '#validate_delegation' do
    context 'without delegation policy' do
      it 'allows delegation by default' do
        result = service.validate_delegation(delegator: delegator, delegate: delegate_agent)
        expect(result[:allowed]).to be true
      end
    end

    context 'with delegation policy' do
      let!(:policy) do
        create(:ai_delegation_policy, account: account, agent: delegator,
               max_depth: 2, allowed_delegate_types: ['assistant'],
               delegatable_actions: ['read_data', 'execute_tool'])
      end

      it 'allows valid delegation' do
        result = service.validate_delegation(
          delegator: delegator, delegate: delegate_agent,
          task: { action_type: 'read_data' }
        )
        expect(result[:allowed]).to be true
      end

      it 'rejects disallowed action types' do
        result = service.validate_delegation(
          delegator: delegator, delegate: delegate_agent,
          task: { action_type: 'delete_data' }
        )
        expect(result[:allowed]).to be false
        expect(result[:reason]).to include('not delegatable')
      end

      it 'rejects disallowed delegate types' do
        specialized = create(:ai_agent, account: account, agent_type: 'data_analyst')
        result = service.validate_delegation(
          delegator: delegator, delegate: specialized
        )
        expect(result[:allowed]).to be false
        expect(result[:reason]).to include('not in allowed types')
      end
    end
  end

  describe '#effective_capabilities' do
    let!(:trust_score) { create(:ai_agent_trust_score, :trusted, account: account, agent: delegator) }

    it 'returns capabilities with delegation policy' do
      result = service.effective_capabilities(agent: delegator)
      expect(result[:tier]).to eq('trusted')
      expect(result[:capabilities]).to be_present
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AutonomyGate do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account) }

  before do
    Ai::InterventionPolicy.register_category!('test.action')

    # Provide a no-op test executor that the gate can invoke during the
    # :proceed branch without touching real domain models.
    stub_const('TestSpecExecutor', Class.new do
      def self.execute(params, deferred_operation:)
        { success: true, data: { ran_with: params } }
      end

      def self.preview(_params)
        { summary: 'Test action', impact: 'None' }
      end
    end)
  end

  let(:base_args) do
    {
      action_category: 'test.action',
      executor_class: 'TestSpecExecutor',
      params: { foo: 'bar' },
      account: account,
      requested_by: user
    }
  end

  describe '.evaluate' do
    context 'when policy resolves to auto_approve' do
      before do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'global', policy: 'auto_approve', priority: 5, is_active: true
        )
      end

      it 'returns :proceed and runs the executor synchronously' do
        result = described_class.evaluate(**base_args)
        expect(result.decision).to eq(:proceed)
        expect(result.result).to include(success: true)
        expect(result.deferred_operation).to be_present
        expect(result.deferred_operation.status).to eq('completed')
      end

      it 'records the deferred operation with executor output' do
        result = described_class.evaluate(**base_args)
        op = result.deferred_operation.reload
        expect(op.action_category).to eq('test.action')
        expect(op.executor_class).to eq('TestSpecExecutor')
        expect(op.params).to eq('foo' => 'bar')
        expect(op.executed_at).to be_present
      end
    end

    context 'when policy resolves to require_approval' do
      before do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'global', policy: 'require_approval', priority: 5, is_active: true
        )
      end

      it 'returns :pending without executing' do
        result = described_class.evaluate(**base_args)
        expect(result.decision).to eq(:pending)
        expect(result.deferred_operation.status).to eq('pending')
        expect(result.deferred_operation.executed_at).to be_nil
      end

      it 'creates an Ai::ApprovalRequest linked to the deferred operation' do
        result = described_class.evaluate(**base_args)
        request = result.deferred_operation.approval_request
        expect(request).to be_present
        expect(request.source_type).to eq('Ai::DeferredOperation')
        expect(request.source_id).to eq(result.deferred_operation.id)
        expect(request.status).to eq('pending')
      end

      it 'reuses the chain assigned to the policy when set' do
        chain = Ai::ApprovalChain.create!(
          account: account, name: 'Custom', trigger_type: 'autonomy_action',
          status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
          steps: [{ 'name' => 'Step', 'approvers' => ['*'], 'required_approvals' => 1 }]
        )
        Ai::InterventionPolicy.find_by(action_category: 'test.action').update!(approval_chain: chain)

        result = described_class.evaluate(**base_args)
        expect(result.deferred_operation.approval_request.approval_chain_id).to eq(chain.id)
      end
    end

    context 'when policy resolves to block' do
      before do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'global', policy: 'block', priority: 5, is_active: true
        )
      end

      it 'returns :blocked with an error message' do
        result = described_class.evaluate(**base_args)
        expect(result.decision).to eq(:blocked)
        expect(result.error).to include('blocked by policy')
        expect(result.deferred_operation.status).to eq('rejected')
      end
    end

    context 'when no policy is configured (default)' do
      it 'falls through to require_approval per InterventionPolicyService default' do
        result = described_class.evaluate(**base_args)
        expect(result.decision).to eq(:pending)
      end
    end

    context 'with agent attribution' do
      before do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'agent', ai_agent_id: agent.id,
          policy: 'auto_approve', priority: 10, is_active: true
        )
      end

      it 'prefers agent-scoped policy over global' do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'global', policy: 'require_approval', priority: 5, is_active: true
        )

        result = described_class.evaluate(**base_args.merge(agent: agent))
        expect(result.decision).to eq(:proceed)
      end

      it 'attaches the agent to the deferred operation row' do
        result = described_class.evaluate(**base_args.merge(agent: agent))
        expect(result.deferred_operation.ai_agent_id).to eq(agent.id)
      end
    end
  end
end

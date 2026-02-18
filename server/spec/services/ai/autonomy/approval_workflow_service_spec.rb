# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Autonomy::ApprovalWorkflowService do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:user) { create(:user, account: account) }
  let(:approver) { create(:user, account: account) }
  let(:service) { described_class.new(account: account) }

  describe '#request_approval' do
    it 'creates a pending approval request' do
      request = service.request_approval(
        agent: agent,
        action_type: 'spawn_agent',
        description: 'Agent wants to spawn a child',
        requested_by: user
      )

      expect(request).to be_persisted
      expect(request.status).to eq('pending')
      expect(request.request_data['agent_id']).to eq(agent.id)
      expect(request.request_data['action_type']).to eq('spawn_agent')
      expect(request.expires_at).to be > Time.current
    end

    it 'creates an autonomy approval chain if none exists' do
      expect {
        service.request_approval(agent: agent, action_type: 'execute_code', description: 'Test')
      }.to change(Ai::ApprovalChain, :count).by(1)

      chain = Ai::ApprovalChain.last
      expect(chain.trigger_type).to eq('autonomy_action')
      expect(chain.name).to eq('autonomy_execute_code')
    end
  end

  describe '#pending_approvals' do
    it 'returns only pending requests for the account' do
      service.request_approval(agent: agent, action_type: 'test', description: 'Test 1')
      service.request_approval(agent: agent, action_type: 'test2', description: 'Test 2')

      pending = service.pending_approvals
      expect(pending.count).to eq(2)
      expect(pending.all? { |r| r.status == 'pending' }).to be true
    end
  end

  describe '#approve' do
    let!(:request) do
      service.request_approval(agent: agent, action_type: 'test', description: 'Test')
    end

    it 'approves a pending request' do
      result = service.approve(request: request, approver: approver, comments: 'Looks good')

      expect(result).to be true
      expect(request.reload.status).to eq('approved')
      expect(request.completed_at).to be_present
      expect(request.decisions.count).to eq(1)
      expect(request.decisions.first.decision).to eq('approved')
    end

    it 'does not approve already-approved requests' do
      request.update!(status: 'approved', completed_at: Time.current)
      result = service.approve(request: request, approver: approver)
      expect(result).to be false
    end
  end

  describe '#reject' do
    let!(:request) do
      service.request_approval(agent: agent, action_type: 'test', description: 'Test')
    end

    it 'rejects a pending request' do
      result = service.reject(request: request, approver: approver, comments: 'Too risky')

      expect(result).to be true
      expect(request.reload.status).to eq('rejected')
      expect(request.decisions.first.decision).to eq('rejected')
    end
  end

  describe '#expire_overdue!' do
    it 'expires requests past their deadline' do
      request = service.request_approval(agent: agent, action_type: 'test', description: 'Test')
      request.update!(expires_at: 1.hour.ago)

      service.expire_overdue!
      expect(request.reload.status).to eq('expired')
    end
  end
end

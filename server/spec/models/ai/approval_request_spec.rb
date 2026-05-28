# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ApprovalRequest, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:approver) { user_with_permissions('system.infra_tasks.control') }

  def make_chain(steps:)
    Ai::ApprovalChain.create!(
      account: account, name: "chain-#{SecureRandom.hex(4)}",
      trigger_type: 'autonomy_action', status: 'active',
      is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
      steps: steps
    )
  end

  describe '#can_approve? with typed approver specs' do
    it 'returns true for the wildcard "*"' do
      chain = make_chain(steps: [{
        'name' => 's1', 'approvers' => ['*'], 'required_approvals' => 1
      }])
      req = chain.create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      expect(req.can_approve?(user)).to be true
    end

    it 'returns true for matching permission' do
      chain = make_chain(steps: [{
        'name' => 's1',
        'approvers' => [{ 'type' => 'permission', 'value' => 'system.infra_tasks.control' }],
        'required_approvals' => 1
      }])
      req = chain.create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      expect(req.can_approve?(approver)).to be true
      expect(req.can_approve?(user)).to be false
    end

    it 'returns true for matching user UUID hash form' do
      chain = make_chain(steps: [{
        'name' => 's1',
        'approvers' => [{ 'type' => 'user', 'value' => user.id.to_s }],
        'required_approvals' => 1
      }])
      req = chain.create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      expect(req.can_approve?(user)).to be true
    end

    it 'rejects unknown approver types at chain validation time' do
      # Phase 1c step-shape validation prevents malformed shapes from ever
      # persisting, which makes the runtime `can_approve?` path for unknown
      # types unreachable in production. The validation IS the contract.
      expect {
        make_chain(steps: [{
          'name' => 's1',
          'approvers' => [{ 'type' => 'group', 'value' => 'something' }],
          'required_approvals' => 1
        }])
      }.to raise_error(ActiveRecord::RecordInvalid, /type must be one of/)
    end
  end

  describe 'multi-step advancement via record_decision!' do
    it 'advances current_step when first step threshold is met' do
      chain = make_chain(steps: [
        { 'name' => 'Step 1', 'approvers' => ['*'], 'required_approvals' => 1 },
        { 'name' => 'Step 2', 'approvers' => ['*'], 'required_approvals' => 1 }
      ])
      req = chain.create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')

      req.record_decision!(approver: user, decision: 'approved')
      expect(req.reload.current_step).to eq(1)
      expect(req.status).to eq('pending')

      req.record_decision!(approver: user, decision: 'approved')
      expect(req.reload.status).to eq('approved')
    end

    it 'rejects mid-chain on a single rejection' do
      chain = make_chain(steps: [
        { 'name' => 's1', 'approvers' => ['*'], 'required_approvals' => 1 },
        { 'name' => 's2', 'approvers' => ['*'], 'required_approvals' => 1 }
      ])
      req = chain.create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')

      req.record_decision!(approver: user, decision: 'approved')
      req.record_decision!(approver: user, decision: 'rejected')
      expect(req.reload.status).to eq('rejected')
    end
  end

  describe 'polymorphic source notification (after_update)' do
    it 'invokes source.on_approval_decision when status flips' do
      probe = Class.new do
        attr_accessor :captured
        def find_by(id:)
          @last = self
        end
        def on_approval_decision(request)
          @captured = request.status
        end
      end.new
      stub_const('SpecSource', probe)
      probe.singleton_class.define_method(:find_by) { |id:| probe }
      probe.singleton_class.define_method(:respond_to?) { |m| m == :find_by || super(m) }

      chain = make_chain(steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }])
      req = chain.create_request!(
        source_type: 'SpecSource', source_id: SecureRandom.uuid, description: 'd'
      )
      req.record_decision!(approver: user, decision: 'approved')
      expect(probe.captured).to eq('approved')
    end

    it 'logs and continues if source class does not exist' do
      chain = make_chain(steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }])
      req = chain.create_request!(
        source_type: 'Nonexistent::Class', source_id: SecureRandom.uuid, description: 'd'
      )
      expect { req.record_decision!(approver: user, decision: 'approved') }.not_to raise_error
      expect(req.reload.status).to eq('approved')
    end
  end
end

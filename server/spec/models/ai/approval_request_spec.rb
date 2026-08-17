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

  # IMP-4bbb4227ac8a — post-approval executor failures were invisible: the
  # execute-on-approval dispatch (#notify_source_of_decision) rescued and only
  # logged, so an approved action that failed left the request "approved", the
  # operation failed-or-stranded, and no operator-visible signal anywhere.
  # These examples pin the declared outcome on both records plus the
  # operator-visible Ai::ExecutionEvent (surfaced via platform.recent_events).
  describe 'post-approval execution outcome' do
    let(:chain) do
      make_chain(steps: [{ 'name' => 's', 'approvers' => ['*'], 'required_approvals' => 1 }])
    end

    def gated_operation(executor_class)
      Ai::DeferredOperation.create!(
        account: account, action_category: 'test.act',
        executor_class: executor_class, params: { 'k' => 'v' }
      )
    end

    def request_for(op)
      chain.create_request!(
        source_type: 'Ai::DeferredOperation', source_id: op.id, description: 'd'
      )
    end

    before do
      stub_const('SucceedingPerformer', Class.new do
        def self.execute(params, deferred_operation:)
          { performed: true, params: params }
        end
      end)
      stub_const('ExplodingPerformer', Class.new do
        def self.execute(_params, deferred_operation:)
          raise 'post-approval kaboom'
        end
      end)
    end

    context 'when the executor raises after approval' do
      it 'declares the failure on the request, the operation, and an operator-visible event' do
        op = gated_operation('ExplodingPerformer')
        req = request_for(op)

        # Approval semantics unchanged: the decision itself still succeeds.
        expect { req.record_decision!(approver: user, decision: 'approved') }
          .not_to raise_error

        req.reload
        expect(req.status).to eq('approved')
        expect(req.execution_status).to eq('failed')
        expect(req.execution_error).to include('post-approval kaboom')

        # Declared outcome on the operation (existing fail! mechanics, pinned).
        expect(op.reload.status).to eq('failed')
        expect(op.error_message).to include('post-approval kaboom')

        event = Ai::ExecutionEvent.find_by(
          source_type: 'Ai::ApprovalRequest', source_id: req.id
        )
        expect(event).to be_present
        expect(event.account_id).to eq(account.id)
        expect(event.status).to eq('failed')
        expect(event.error_class).to eq('RuntimeError')
        expect(event.error_message).to include('post-approval kaboom')
        expect(event.metadata).to include(
          'operation_source_type' => 'Ai::DeferredOperation',
          'operation_source_id' => op.id
        )
      end
    end

    context 'when the executor succeeds (positive twin)' do
      it 'behaves exactly as before and declares success with no failure event' do
        op = gated_operation('SucceedingPerformer')
        req = request_for(op)

        req.record_decision!(approver: user, decision: 'approved')

        req.reload
        expect(req.status).to eq('approved')
        expect(req.execution_status).to eq('succeeded')
        expect(req.execution_error).to be_nil

        expect(op.reload.status).to eq('completed')
        expect(op.result).to include('performed' => true)

        expect(
          Ai::ExecutionEvent.where(source_type: 'Ai::ApprovalRequest', source_id: req.id)
        ).to be_empty
      end
    end

    it 'declares nothing for a rejected decision — no execution happened' do
      op = gated_operation('SucceedingPerformer')
      req = request_for(op)

      req.record_decision!(approver: user, decision: 'rejected')

      req.reload
      expect(req.status).to eq('rejected')
      expect(req.execution_status).to be_nil
      expect(req.execution_error).to be_nil
      expect(op.reload.status).to eq('rejected')
    end

    it 'declares nothing when the approved request has no executable source' do
      req = chain.create_request!(
        source_type: 'X', source_id: SecureRandom.uuid, description: 'd'
      )

      req.record_decision!(approver: user, decision: 'approved')

      req.reload
      expect(req.status).to eq('approved')
      expect(req.execution_status).to be_nil
    end

    # IMP-5547989e2bbd — the no-op arm, and the reason the source reports rather
    # than the caller inferring. Every implementation of the hook guards with an
    # early return (already executed, cancelled, no longer parked at this gate),
    # and to anyone watching only for exceptions that return is indistinguishable
    # from a dispatch that ran. It used to stamp "succeeded": a false success on
    # the very surface IMP-4bbb4227ac8a built to end false silence.
    it 'declares nothing when an approved source reports it did not act' do
      op = gated_operation('SucceedingPerformer')
      # Resolved before the decision lands, so #on_approval_decision takes its
      # `return unless pending?` guard and reports DISPATCH_NOOP.
      op.update_columns(status: 'completed')
      req = request_for(op)

      req.record_decision!(approver: user, decision: 'approved')

      req.reload
      expect(req.status).to eq('approved')
      expect(req.execution_status).to be_nil
      expect(req.execution_error).to be_nil
      # The guard genuinely held — the executor never ran a second time.
      expect(op.reload.result).to be_blank
      expect(
        Ai::ExecutionEvent.where(source_type: 'Ai::ApprovalRequest', source_id: req.id)
      ).to be_empty
    end

    # A source written before this contract (or a test double) says nothing the
    # vocabulary recognises. "Cannot say" must land on nil — the existing state
    # for "nothing to declare" — not on an assertion nobody verified.
    it 'declares nothing when the source answers outside the dispatch vocabulary' do
      probe = Class.new do
        def on_approval_decision(_request)
          :something_else
        end
      end.new
      stub_const('UnversionedSource', probe)
      probe.singleton_class.define_method(:find_by) { |id:| probe }
      probe.singleton_class.define_method(:respond_to?) { |m| m == :find_by || super(m) }

      req = chain.create_request!(
        source_type: 'UnversionedSource', source_id: SecureRandom.uuid, description: 'd'
      )
      req.record_decision!(approver: user, decision: 'approved')

      req.reload
      expect(req.status).to eq('approved')
      expect(req.execution_status).to be_nil
    end
  end
end

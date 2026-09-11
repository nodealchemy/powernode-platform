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

  # C3b1 F1 / C3b2 B2: the step-decision push. A decision that neither advances
  # the step nor resolves the request moves no column the after_update callbacks
  # watch, so the step's other approvers, and every open queue, kept a stale
  # count until something else changed. The lead's ruling: the "Approval
  # needed" card goes only to people who can still act on the step that is now
  # current (never to whoever already decided it), and a content-free
  # queue-refresh event reaches every viewer of the queue, the decider included.
  describe 'a decision reaches the people who can still act on the step (record_decision!)' do
    let(:perm) { 'system.infra_tasks.control' }
    let!(:approver_a) { user_with_permissions(perm, 'ai.agents.read', account: account) }
    let!(:approver_b) { user_with_permissions(perm, 'ai.agents.read', account: account) }
    let!(:observer)   { user_with_permissions('ai.agents.read', account: account) }
    let!(:bystander)  { user_without_permissions(account: account) }

    def cards_for(recipient, req)
      Notification.where(user_id: recipient.id)
                  .where("metadata->>'approval_request_id' = ?", req.id.to_s)
                  .count
    end

    def by_permission(name, required)
      { 'name' => name, 'approvers' => [ { 'type' => 'permission', 'value' => perm } ],
        'required_approvals' => required }
    end

    def two_key_request
      make_chain(steps: [ by_permission('Two keys', 2) ])
        .create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
    end

    # The queue-refresh events, as [recipient id, payload], captured at the one
    # publishing primitive and still delivered.
    def capture_queue_events
      events = []
      allow(NotificationChannel).to receive(:broadcast_to_user).and_wrap_original do |original, user, data|
        events << [ user.id, data ] if data[:type] == 'approval_request_changed'
        original.call(user, data)
      end
      events
    end

    it 'sends the card once to each approver who has not decided the step — and not to the decider' do
      req = two_key_request
      before = [ approver_a, approver_b, observer, bystander ].to_h { |u| [ u.id, cards_for(u, req) ] }

      req.record_decision!(approver: approver_a, decision: 'approved')

      # Neither watched column moved: this is exactly the decision that went unheard.
      expect(req.reload.current_step).to eq(0)
      expect(req.status).to eq('pending')
      expect(cards_for(approver_b, req) - before[approver_b.id]).to eq(1)
      expect(cards_for(approver_a, req) - before[approver_a.id]).to eq(0)
      # The card carries its recipient's own can-act (C3b2 review B1).
      latest_b = Notification.where(user_id: approver_b.id).order(:created_at).last
      expect(latest_b.metadata['current_step_can_approve']).to be(true)
      expect(cards_for(observer, req) - before[observer.id]).to eq(0)
      expect(cards_for(bystander, req) - before[bystander.id]).to eq(0)
    end

    it 'sends a step advance to the new step\'s approvers exactly once — the decider too, when eligible there' do
      req = make_chain(steps: [ by_permission('First', 1), by_permission('Second', 1) ])
              .create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      before = { a: cards_for(approver_a, req), b: cards_for(approver_b, req) }

      req.record_decision!(approver: approver_a, decision: 'approved')

      expect(req.reload.current_step).to eq(1)
      # Once, not once for the advance and again for the decision.
      expect(cards_for(approver_b, req) - before[:b]).to eq(1)
      expect(cards_for(approver_a, req) - before[:a]).to eq(1)
      latest = Notification.where(user_id: approver_a.id).order(:created_at).last
      expect(latest.metadata['current_step']).to eq(1)
    end

    it 'leaves the decider out of a step advance when they are not an approver of the new step' do
      req = make_chain(steps: [
        by_permission('First', 1),
        { 'name' => 'Second', 'approvers' => [ { 'type' => 'user', 'value' => approver_b.id.to_s } ], 'required_approvals' => 1 }
      ]).create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      before = { a: cards_for(approver_a, req), b: cards_for(approver_b, req) }

      req.record_decision!(approver: approver_a, decision: 'approved')

      expect(req.reload.current_step).to eq(1)
      expect(cards_for(approver_b, req) - before[:b]).to eq(1)
      expect(cards_for(approver_a, req) - before[:a]).to eq(0)
    end

    it 'tells every viewer of the queue the request changed, the decider included, each with their own can-act' do
      req = two_key_request
      events = capture_queue_events

      req.record_decision!(approver: approver_a, decision: 'approved')

      # Exactly one event per viewer who may read the queue, and none for a user who may not.
      expect(events.map(&:first)).to contain_exactly(approver_a.id, approver_b.id, observer.id)
      by_user = events.to_h
      expect(by_user.values).to all(include(approval_request_id: req.id, status: 'pending', current_step: 0))
      expect(by_user[approver_a.id][:current_step_can_approve]).to be(false) # already decided
      expect(by_user[approver_b.id][:current_step_can_approve]).to be(true)
      expect(by_user[observer.id][:current_step_can_approve]).to be(false)
    end

    it "announces the decision only after the lock's transaction has closed" do
      req = two_key_request
      baseline = ActiveRecord::Base.connection.open_transactions
      open_at_event = []
      allow(NotificationChannel).to receive(:broadcast_to_user).and_wrap_original do |original, user, data|
        open_at_event << ActiveRecord::Base.connection.open_transactions if data[:type] == 'approval_request_changed'
        original.call(user, data)
      end

      req.record_decision!(approver: approver_a, decision: 'approved')

      # A queue that re-reads on the event must find the decision committed.
      expect(open_at_event).not_to be_empty
      expect(open_at_event).to all(eq(baseline))
    end

    it 'sends nothing from the decision once the request is resolved' do
      req = two_key_request
      before = cards_for(approver_b, req)
      events = capture_queue_events

      req.record_decision!(approver: approver_a, decision: 'rejected')

      expect(req.reload.status).to eq('rejected')
      expect(cards_for(approver_b, req) - before).to eq(0)
      expect(events).to be_empty
    end

    it 'sends no queue event from the decision when the step moved — the advance callback carries that' do
      req = make_chain(steps: [ by_permission('First', 1), by_permission('Second', 1) ])
              .create_request!(source_type: 'X', source_id: SecureRandom.uuid, description: 'd')
      events = capture_queue_events

      req.record_decision!(approver: approver_a, decision: 'approved')

      expect(req.reload.current_step).to eq(1)
      expect(events).to be_empty
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

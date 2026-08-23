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

      def self.preview(_params, deferred_operation: nil)
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

    # IMP-73dff8186c1e — the operator-facing half of the notification-cap
    # defect. `requested_by` is always populated on the HTTP path, so this is
    # the audience for which "max_daily_notifications" was actually live: once
    # the day's budget was spent, resolution returned "silent" and the
    # `when "block", "silent"` branch below rejected the operation as 422.
    context 'when a notify_and_proceed policy has spent its notification budget' do
      before do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'test.action',
          scope: 'global', policy: 'notify_and_proceed', priority: 5, is_active: true,
          conditions: { 'max_daily_notifications' => 1 }
        )
      end

      # Explicitly called, not eager — a plain method rather than a `let!` so the
      # headroom example below can skip it.
      def over_cap!
        create(:notification, account: account, user: user,
                              notification_type: 'agent_status_update', category: 'ai')
      end

      it 'parks the write for approval instead of refusing it' do
        over_cap!

        result = described_class.evaluate(**base_args)

        expect(result.decision).to eq(:pending)
        expect(result.deferred_operation.approval_request).to be_present
      end

      # The audit row is what an operator reads back, and a rejection there is
      # the durable half of the old behaviour.
      it 'leaves no policy rejection on the audit row' do
        over_cap!

        op = described_class.evaluate(**base_args).deferred_operation.reload

        expect(op.status).to eq('pending')
        expect(op.error_message).to be_nil
      end

      # Positive twin: the relaxation the operator asked for still applies while
      # the budget has headroom, so the cap is not simply inert.
      it 'still proceeds inline while the budget has headroom' do
        result = described_class.evaluate(**base_args)

        expect(result.decision).to eq(:proceed)
        expect(result.deferred_operation.reload.status).to eq('completed')
      end

      # IMP-e43194754178 — parking is itself a notification emitter, and the
      # amplification is the ACCEPTED contract (IMP-e75e843bd42b): the
      # ApprovalRequest's after_create fan-out sends one category-"ai"
      # Notification per approver, and the default chain #resolve_chain builds
      # carries ["*"], which Ai::ApprovalRequestNotifier resolves to every
      # ACTIVE user. Until now that lived only in a source comment; a change
      # to the default chain's audience or the fan-out's active-user cut
      # would move it undetected. Pinned here on the gate's own parked path —
      # the e2e example in intervention_policy_service_spec fabricates its
      # request from a factory with hardcoded step approvers, so it cannot
      # see a change to the chain the gate actually builds.
      it 'fans out one category-"ai" notification per active user when it parks' do
        over_cap!
        others = create_list(:user, 2, account: account)
        create(:user, :inactive, account: account)
        audience = [user, *others]

        result = nil
        expect {
          result = described_class.evaluate(**base_args)
        }.to change { Notification.where(account_id: account.id, category: 'ai').count }.by(audience.size)

        request = result.deferred_operation.approval_request
        fan_out = Notification.where(account_id: account.id, category: 'ai')
                              .where("metadata ->> 'approval_request_id' = ?", request.id)
        expect(fan_out.pluck(:user_id)).to match_array(audience.map(&:id))
      end

      # The contrast that makes the fan-out an AMPLIFICATION: the healthy
      # under-cap path emits nothing — the gate never notifies on :proceed —
      # so an exhausted budget strictly increases volume on the category.
      it 'emits nothing on the healthy under-cap proceed' do
        create_list(:user, 2, account: account)

        result = nil
        expect {
          result = described_class.evaluate(**base_args)
        }.not_to change { Notification.where(account_id: account.id).count }

        # :proceed, specifically — :blocked would also emit nothing.
        expect(result.decision).to eq(:proceed)
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

    # IMP-b44483c3c098 — the params→request_data copy is the one place every
    # gated call site passes through, so redacting here is what makes both of
    # federation acceptance's producers (the MCP tool today, the REST PATCH
    # next) safe without either of them knowing about it.
    context 'when params carry secret material' do
      let(:plaintext) { 'SINGLE-USE-TOKEN-PLAINTEXT' }
      let(:captured)  { [] }

      let(:secret_args) do
        base_args.merge(
          executor_class: 'CapturingSpecExecutor',
          params: { federation_peer_id: 'peer-42', acceptance_token: plaintext }
        )
      end

      before do
        sink = captured
        stub_const('CapturingSpecExecutor', Class.new do
          define_singleton_method(:execute) do |params, deferred_operation:|
            sink << params.deep_dup
            { success: true, data: { accepted: true } }
          end

          define_singleton_method(:preview) do |_params, deferred_operation: nil|
            { summary: 'Accept federation peer', impact: 'Handshake completes' }
          end
        end)
      end

      context 'under require_approval' do
        before do
          Ai::InterventionPolicy.create!(
            account: account, action_category: 'test.action',
            scope: 'global', policy: 'require_approval', priority: 5, is_active: true
          )
        end

        it 'keeps the secret out of the approval request an approver reads' do
          request = described_class.evaluate(**secret_args).deferred_operation.approval_request

          expect(request.request_data.to_json).not_to include(plaintext)
          expect(request.request_data.dig('params', 'acceptance_token')).to eq('[FILTERED]')
        end

        it 'leaves the non-secret params legible on the approval card' do
          request = described_class.evaluate(**secret_args).deferred_operation.approval_request

          expect(request.request_data.dig('params', 'federation_peer_id')).to eq('peer-42')
          expect(request.request_data['executor_class']).to eq('CapturingSpecExecutor')
        end

        # The other direction: redacting the approver's copy must not disarm the
        # executor, which cannot complete the handshake without the real token.
        it 'still hands the executor the raw secret when the approval completes' do
          op = described_class.evaluate(**secret_args).deferred_operation
          op.approval_request.update!(status: 'approved')

          expect(op.reload.status).to eq('completed')
          expect(captured.last['acceptance_token']).to eq(plaintext)
        end
      end

      context 'under auto_approve' do
        before do
          Ai::InterventionPolicy.create!(
            account: account, action_category: 'test.action',
            scope: 'global', policy: 'auto_approve', priority: 5, is_active: true
          )
        end

        # No approval request exists on this branch, so params are the only copy
        # — and the executor must still get the real value inline.
        it 'hands the executor the raw secret and stores it unredacted for the replay' do
          op = described_class.evaluate(**secret_args).deferred_operation

          expect(captured.last['acceptance_token']).to eq(plaintext)
          expect(op.reload.params['acceptance_token']).to eq(plaintext)
        end
      end
    end
  end
end

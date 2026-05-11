# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DeferredOperation, type: :model do
  let(:account) { create(:account) }
  let(:chain) do
    Ai::ApprovalChain.create!(
      account: account, name: 'Test', trigger_type: 'autonomy_action',
      status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
      steps: [{ 'name' => 'Step', 'approvers' => ['*'], 'required_approvals' => 1 }]
    )
  end

  before do
    stub_const('TestPerformer', Class.new do
      def self.execute(params, deferred_operation:)
        { performed: true, params: params }
      end

      def self.preview(_params)
        { summary: 'Test perform' }
      end
    end)
  end

  def make_op(status: 'pending')
    described_class.create!(
      account: account, action_category: 'test.act',
      executor_class: 'TestPerformer',
      status: status, params: { 'k' => 'v' }
    )
  end

  describe 'AASM transitions' do
    it 'starts in pending and can advance through approve → executing → completed' do
      op = make_op
      expect(op.status).to eq('pending')
      op.approve!
      expect(op.status).to eq('approved')
      op.start_execution!
      expect(op.status).to eq('executing')
      op.complete!({ 'result' => 'ok' })
      expect(op.status).to eq('completed')
      expect(op.result).to eq('result' => 'ok')
      expect(op.executed_at).to be_present
    end

    it 'rejects from pending without execution' do
      op = make_op
      op.reject!
      expect(op.status).to eq('rejected')
    end

    it 'fails with error message capture' do
      op = make_op
      op.approve!
      op.start_execution!
      op.fail!(StandardError.new('boom'))
      expect(op.status).to eq('failed')
      expect(op.error_message).to include('boom')
    end
  end

  describe '#execute_now!' do
    it 'transitions through approve → executing → completed and captures result' do
      op = make_op
      result = op.execute_now!
      expect(result).to include(performed: true)
      expect(op.reload.status).to eq('completed')
      expect(op.result).to include('performed' => true)
    end

    it 'transitions to failed on executor exception' do
      stub_const('FailingExecutor', Class.new do
        def self.execute(_params, deferred_operation:)
          raise 'kaboom'
        end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'FailingExecutor', params: {}
      )
      expect { op.execute_now! }.to raise_error(/kaboom/)
      expect(op.reload.status).to eq('failed')
      expect(op.error_message).to include('kaboom')
    end
  end

  describe '#on_approval_decision' do
    let(:request) do
      chain.create_request!(
        source_type: 'Ai::DeferredOperation',
        source_id: SecureRandom.uuid,
        description: 'test',
        request_data: {}
      )
    end

    it 'executes the operation when approval flips to approved' do
      op = make_op
      request.update!(source_id: op.id)
      request.update!(status: 'approved')  # bypass record_decision! for direct test
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('completed')
    end

    it 'rejects the operation when approval flips to rejected' do
      op = make_op
      request.update!(source_id: op.id, status: 'rejected')
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('rejected')
    end

    it 'expires the operation when approval expires' do
      op = make_op
      request.update!(source_id: op.id, status: 'expired')
      op.on_approval_decision(request)
      expect(op.reload.status).to eq('expired')
    end

    it 'is a no-op for already-decided operations (idempotent)' do
      op = make_op
      op.approve!
      op.start_execution!
      op.complete!({})
      request.update!(source_id: op.id, status: 'approved')
      expect { op.on_approval_decision(request) }.not_to change { op.reload.status }
    end
  end

  describe '#preview' do
    it 'returns the executor preview output' do
      op = make_op
      expect(op.preview).to include(summary: 'Test perform')
    end

    it 'gracefully handles preview exceptions' do
      stub_const('NoPreviewExecutor', Class.new do
        def self.execute(*); end
      end)
      op = described_class.create!(
        account: account, action_category: 'test.act',
        executor_class: 'NoPreviewExecutor', params: {}
      )
      expect(op.preview).to include(summary: 'test.act')
    end
  end
end

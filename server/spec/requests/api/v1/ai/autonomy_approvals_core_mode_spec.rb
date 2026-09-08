# frozen_string_literal: true

require 'rails_helper'

# IMP-27e2f8e59ce0 — on a deployment with NO governance-providing extension
# (ops-hub: only the system extension), Ai::AutonomyGate still parks a
# require_approval action behind an Ai::ApprovalRequest (the chain models are
# core), but POST .../approvals/:id/approve answered 422 "Cannot approve this
# request" because ApprovalWorkflowService#approve refused without the
# capability. The operator could see the card and never decide it; the
# deferred operation stayed stranded. This pins the whole path with the
# capability ABSENT: park, then approve, then the operation runs.
RSpec.describe 'Autonomy approvals are decidable without a governance extension', type: :request do
  let(:account) { create(:account) }
  let(:approver) { create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve]) }
  let(:headers) { auth_headers_for(approver) }

  before do
    allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
    allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(false)

    ::Ai::InterventionPolicy.register_category!('test.core_mode_action')
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: 'test.core_mode_action',
      scope: 'global', policy: 'require_approval', priority: 5, is_active: true
    )
    stub_const('CoreModeSpecExecutor', Class.new do
      class << self
        attr_accessor :ran
      end

      def self.execute(_params, deferred_operation:)
        self.ran = (ran || 0) + 1
        { success: true, data: { ok: true } }
      end

      def self.preview(_params, deferred_operation: nil)
        { summary: 'core-mode action', impact: 'none' }
      end
    end)
  end

  let!(:gate_result) do
    ::Ai::AutonomyGate.evaluate(
      action_category: 'test.core_mode_action', executor_class: 'CoreModeSpecExecutor',
      params: { attributes: { name: 'x' } }, account: account, requested_by: approver,
      description: 'core-mode gated action'
    )
  end
  let(:deferred) { gate_result.deferred_operation }
  let(:approval_request) { deferred.approval_request }

  it 'parks the action behind a request (premise)' do
    expect(Ai::Autonomy::ApprovalWorkflowService.governance_enabled?).to be(false)
    expect(gate_result.decision).to eq(:pending)
    expect(approval_request).to be_present
    expect(CoreModeSpecExecutor.ran).to be_nil
  end

  it 'approves the request and runs the parked operation' do
    post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/approve", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(approval_request.reload.status).to eq('approved')
    expect(deferred.reload.status).to eq('completed')
    expect(CoreModeSpecExecutor.ran).to eq(1)
  end

  it 'rejects the request and leaves the operation unexecuted' do
    post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/reject", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(approval_request.reload.status).to eq('rejected')
    expect(CoreModeSpecExecutor.ran).to be_nil
  end
end

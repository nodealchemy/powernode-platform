# frozen_string_literal: true

require 'rails_helper'

# IMP-b44483c3c098 — a gated operation whose params carry secret material must
# not disclose that material to the approval audience.
#
# Ai::AutonomyGate stores caller-supplied params verbatim (the executor has to
# consume them after approval) and copies them into
# Ai::ApprovalRequest#request_data. Four read surfaces then serialize that copy
# — or the deferred operation's params directly — to an audience defined by the
# approval permissions, not by the permission that authorised the original call:
#
#   GET /api/v1/ai/autonomy/approvals            → ai.agents.read
#   GET /api/v1/ai/autonomy/approvals/:id        → ai.agents.read (also params:)
#   GET /api/v1/ai/governance/approval_requests  → ai.governance.read
#   GET /api/v1/ai/governance/approval_requests/:id → ai.governance.read
#
# The autonomy pair is the widest: `require_approval_permission` binds only
# approve_action/reject_action, so the reads clear on `validate_permissions`
# (ai.agents.read) alone — wider than the ai.autonomy.approve audience, and far
# wider than the system.sdwan.federation.manage that mints a federation
# acceptance token in the first place.
RSpec.describe 'Approval read surfaces do not disclose secret params', type: :request do
  let(:account) { create(:account) }

  # Deliberately NOT an approver and NOT a governance manager: the point is that
  # the plainest AI-read permission already reaches these payloads.
  let(:reader) do
    create(:user, account: account, permissions: %w[ai.agents.read ai.governance.read])
  end
  let(:headers) { auth_headers_for(reader) }

  let(:plaintext) { 'FEDERATION-ACCEPTANCE-TOKEN-PLAINTEXT' }

  before do
    Ai::InterventionPolicy.register_category!('test.secret_action')
    Ai::InterventionPolicy.create!(
      account: account, action_category: 'test.secret_action',
      scope: 'global', policy: 'require_approval', priority: 5, is_active: true
    )

    stub_const('SecretParamSpecExecutor', Class.new do
      def self.execute(_params, deferred_operation:)
        { success: true, data: { accepted: true } }
      end

      def self.preview(_params)
        { summary: 'Accept federation peer', impact: 'Mutual route advertisement begins' }
      end
    end)
  end

  # The real shape of a gated federation acceptance: one secret param riding
  # alongside the non-secret id the approver actually needs to see.
  let!(:gate_result) do
    Ai::AutonomyGate.evaluate(
      action_category: 'test.secret_action',
      executor_class: 'SecretParamSpecExecutor',
      params: { federation_peer_id: 'peer-42', acceptance_token: plaintext },
      account: account,
      requested_by: reader,
      description: 'Accept federation peer peer-42'
    )
  end

  let(:approval_request) { gate_result.deferred_operation.approval_request }

  it 'gates the operation and links an approval request (premise of the rest)' do
    expect(gate_result.decision).to eq(:pending)
    expect(approval_request).to be_present
  end

  describe 'GET /api/v1/ai/autonomy/approvals' do
    # This one endpoint routes through Ai::Autonomy::ApprovalWorkflowService,
    # which short-circuits to [] unless a governance-providing extension is
    # loaded. Without the stub the response is an empty list and every
    # "does not disclose" assertion here passes vacuously — the sibling
    # positive control is what makes that visible.
    before do
      allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
      allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
    end

    it 'does not disclose the secret param value' do
      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
    end

    it 'still shows the non-secret params an approver needs' do
      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json

      expect(response.body).to include('peer-42')
    end
  end

  describe 'GET /api/v1/ai/autonomy/approvals/:id' do
    # The detailed branch adds serialize_deferred_operation, which reads
    # Ai::DeferredOperation#params directly — a second copy that a fix applied
    # only at the request_data boundary would leave untouched.
    it 'does not disclose the secret param value through request_data or the deferred operation' do
      get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
    end

    it 'still shows the non-secret params on both copies' do
      get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json

      data = json_response_data
      expect(data.dig('request_data', 'params', 'federation_peer_id')).to eq('peer-42')
      expect(data.dig('deferred_operation', 'params', 'federation_peer_id')).to eq('peer-42')
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests' do
    it 'does not disclose the secret param value' do
      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
    end

    it 'still shows the non-secret params an approver needs' do
      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json

      expect(response.body).to include('peer-42')
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests/:id' do
    it 'does not disclose the secret param value' do
      get "/api/v1/ai/governance/approval_requests/#{approval_request.id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
    end
  end

  # Everything above reaches request_data through Ai::AutonomyGate, so the
  # gate's own redaction alone would satisfy it — which would leave the filters
  # on the two READ surfaces certifying nothing. request_data has producers
  # besides the gate (Ai::GovernanceService, Ai::Approvals::Gateway, the mission
  # orchestrator), and every row written before the gate started redacting still
  # holds plaintext. This block writes such a row directly and pins the read.
  describe 'a request_data row the gate did not write' do
    let(:chain) do
      Ai::ApprovalChain.create!(
        account: account, name: 'Direct', trigger_type: 'autonomy_action',
        status: 'active', is_sequential: true, timeout_hours: 4, timeout_action: 'reject',
        steps: [{ 'name' => 'Step', 'approvers' => ['*'], 'required_approvals' => 1 }]
      )
    end

    let!(:legacy_request) do
      chain.create_request!(
        source_type: 'Ai::Agent',
        source_id: SecureRandom.uuid,
        description: 'Written without passing through the gate',
        request_data: { 'action_type' => 'legacy', 'acceptance_token' => plaintext }
      )
    end

    # Pins WHERE the redaction happens: the row really does hold plaintext, so
    # anything the endpoints below withhold is withheld at the read.
    it 'stores the plaintext on the row, unlike a gated write' do
      expect(legacy_request.reload.request_data['acceptance_token']).to eq(plaintext)
    end

    it 'is redacted by the autonomy read surface' do
      get "/api/v1/ai/autonomy/approvals/#{legacy_request.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
      expect(json_response_data.dig('request_data', 'action_type')).to eq('legacy')
    end

    it 'is redacted by the governance read surface' do
      get "/api/v1/ai/governance/approval_requests/#{legacy_request.id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(plaintext)
    end
  end
end

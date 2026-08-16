# frozen_string_literal: true

require 'rails_helper'

# IMP-77645b94151e, at the surface that actually renders the card.
#
# The service spec pins what Ai::SensitiveParams decides. This one pins that the
# decision REACHES an approver, and that the approvals queue resolves the
# pattern set once for the page rather than once per row — a seam wired at one
# end only is indistinguishable from no seam.
#
# Companion to approval_secret_exposure_spec.rb, which is the opposite oracle
# (nothing secret escapes). Both read the same payload; they must stay in
# agreement about which keys are which.
RSpec.describe 'Approval cards keep non-secret control flags legible', type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: %w[ai.agents.read ai.governance.read]) }
  let(:headers) { auth_headers_for(reader) }

  before do
    Ai::InterventionPolicy.register_category!('test.safe_key_action')
    Ai::InterventionPolicy.create!(
      account: account, action_category: 'test.safe_key_action',
      scope: 'global', policy: 'require_approval', priority: 5, is_active: true
    )

    stub_const('SafeKeyParamSpecExecutor', Class.new do
      def self.execute(_params, deferred_operation:)
        { success: true, data: { accepted: true } }
      end

      def self.preview(_params, deferred_operation: nil)
        { summary: 'Propose federation peer', impact: 'Mints a single-use acceptance token' }
      end
    end)
  end

  # The shape Sdwan::Executors::ProposeFederationPeer is handed: two control
  # flags the approver must weigh, one mint they must not see.
  def gate!(peer:)
    Ai::AutonomyGate.evaluate(
      action_category: 'test.safe_key_action',
      executor_class: 'SafeKeyParamSpecExecutor',
      params: {
        federation_peer_id: peer,
        attributes: { generate_token: true, token_ttl_seconds: 900 },
        acceptance_token: 'FEDERATION-ACCEPTANCE-TOKEN-PLAINTEXT'
      },
      account: account,
      requested_by: reader,
      description: "Propose federation peer #{peer}"
    )
  end

  describe 'GET /api/v1/ai/autonomy/approvals' do
    # Ai::Autonomy::ApprovalWorkflowService short-circuits to [] unless a
    # governance-providing extension is loaded, which would make every
    # assertion here pass vacuously (approval_secret_exposure_spec.rb records
    # the same trap). The row-count assertion below is what keeps it visible.
    before do
      allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
      allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
      gate!(peer: 'peer-42')
    end

    it 'renders the token control flags an approver needs to judge the request' do
      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      attributes = json_response_data.dig(0, 'request_data', 'params', 'attributes')
      expect(attributes['generate_token']).to be true
      expect(attributes['token_ttl_seconds']).to eq(900)
    end

    # Positive control on the same payload — the card that gained the flags must
    # not have gained the mint.
    it 'still withholds the mint riding beside them' do
      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json

      params = json_response_data.dig(0, 'request_data', 'params')
      expect(params['acceptance_token']).to eq('[FILTERED]')
      expect(params['federation_peer_id']).to eq('peer-42')
    end

    it 'resolves the sensitive-key setting once for the whole page' do
      gate!(peer: 'peer-43')
      gate!(peer: 'peer-44')
      allow(SiteSetting).to receive(:get).and_call_original

      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json

      expect(json_response_data.size).to eq(3)
      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').once
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests' do
    before { gate!(peer: 'peer-42') }

    it 'renders the control flags and withholds the mint' do
      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      params = json_response_data.dig('approval_requests', 0, 'request_data', 'params')
      expect(params.dig('attributes', 'generate_token')).to be true
      expect(params.dig('attributes', 'token_ttl_seconds')).to eq(900)
      expect(params['acceptance_token']).to eq('[FILTERED]')
    end

    it 'resolves the sensitive-key setting once for the whole page' do
      gate!(peer: 'peer-43')
      gate!(peer: 'peer-44')
      allow(SiteSetting).to receive(:get).and_call_original

      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json

      expect(json_response_data['approval_requests'].size).to eq(3)
      expect(SiteSetting).to have_received(:get).with('ai_sensitive_param_keys').once
    end
  end
end

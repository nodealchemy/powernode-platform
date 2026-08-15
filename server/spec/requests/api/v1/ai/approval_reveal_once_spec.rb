# frozen_string_literal: true

require 'rails_helper'

# IMP-7b81ca22f661 — an executor that MINTS secret material must reveal it
# EXACTLY ONCE, including when the operation was approval-gated.
#
# Ai::DeferredOperation#execute_now! persists Ai::SensitiveParams.filter(result)
# deliberately: the row must not become a durable second copy of a secret
# outside Vault. On the AUTO-APPROVE path that costs nothing — the raw return is
# handed straight back to the caller inline. On the APPROVAL-REQUIRED path it
# costs everything:
#
#   * the original requester already got `pending: true` and left;
#   * the executor runs hours later, inside
#     Ai::ApprovalRequest#notify_source_of_decision, on a source instance that
#     callback loaded itself and discards on return;
#   * the only durable copy is redacted.
#
# So a secret minted on that path is revealed ZERO times — generated and
# immediately destroyed. This is the precondition for gating
# propose_federation_peer (IMP-2795453255c3): its single-use acceptance token
# would be unrecoverable and every approval-gated handshake unmergeable.
#
# The handoff carries the executor's IN-FLIGHT raw return to the APPROVER's
# decision response, once, without ever storing it:
#
#   executor return → DeferredOperation (in memory, one-shot)
#                   → ApprovalRequest    (in memory, one-shot)
#                   → the decision response (REST + MCP)
#
# Redaction at rest is unchanged, and re-asserted here rather than assumed.
RSpec.describe 'Approval decisions reveal a minted secret exactly once', type: :request do
  let(:account) { create(:account) }

  # ai.agents.read clears `validate_permissions`; ai.autonomy.approve clears
  # `require_approval_permission`, which binds only approve/reject.
  let(:approver) do
    create(:user, account: account, permissions: %w[ai.agents.read ai.autonomy.approve])
  end
  let(:headers) { auth_headers_for(approver) }

  let(:minted_secret) { 'MINTED-ACCEPTANCE-TOKEN-SHOWN-ONCE' }

  before do
    ::Ai::InterventionPolicy.register_category!('test.minting_action')
    ::Ai::InterventionPolicy.create!(
      account: account, action_category: 'test.minting_action',
      scope: 'global', policy: 'require_approval', priority: 5, is_active: true
    )

    # The shape of Sdwan::Executors::ProposeFederationPeer: one minted secret
    # returned alongside the non-secret ids, and NOT persisted by the executor
    # (the peer keeps only a digest + expiry).
    stub_const('MintingSpecExecutor', Class.new do
      class << self
        attr_accessor :minted
      end

      def self.execute(_params, deferred_operation:)
        {
          federation_peer_id: 'peer-42',
          acceptance_token_plaintext: minted,
          note: 'Store the acceptance token immediately — it is shown EXACTLY ONCE.'
        }
      end

      def self.preview(_params, deferred_operation: nil)
        { summary: 'Propose federation with https://peer.example' }
      end
    end)
    MintingSpecExecutor.minted = minted_secret
  end

  let!(:gate_result) do
    ::Ai::AutonomyGate.evaluate(
      action_category: 'test.minting_action',
      executor_class: 'MintingSpecExecutor',
      params: { attributes: { remote_instance_url: 'https://peer.example' } },
      account: account,
      requested_by: approver,
      description: 'Propose federation with https://peer.example'
    )
  end

  let(:deferred) { gate_result.deferred_operation }
  let(:approval_request) { deferred.approval_request }

  # Governance capability gates Ai::Autonomy::ApprovalWorkflowService — without
  # it approve/reject return false and every assertion below would be vacuous.
  let(:enable_governance) do
    lambda do
      allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
      allow(Shared::FeatureGateService).to receive(:capability_present?).with(:governance).and_return(true)
    end
  end

  def approve_via_rest!
    post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/approve", headers: headers, as: :json
  end

  it 'defers the operation, so nothing has been minted yet (premise of the rest)' do
    expect(gate_result.decision).to eq(:pending)
    expect(gate_result.result).to be_nil
    expect(deferred.reload.status).to eq('pending')
    expect(approval_request).to be_present
  end

  describe 'POST /api/v1/ai/autonomy/approvals/:id/approve' do
    before { enable_governance.call }

    it "carries the executor's minted secret in the approver's decision response" do
      approve_via_rest!

      expect(response).to have_http_status(:ok)
      expect(json_response_data.dig('revealed_result', 'acceptance_token_plaintext'))
        .to eq(minted_secret)
    end

    it 'carries the non-secret half of the return with it' do
      approve_via_rest!

      expect(json_response_data.dig('revealed_result', 'federation_peer_id')).to eq('peer-42')
    end

    it 'still redacts the secret at rest (redaction-at-rest is not weakened)' do
      approve_via_rest!

      op = deferred.reload
      expect(op.status).to eq('completed')
      expect(op.result['acceptance_token_plaintext']).to eq(::Ai::SensitiveParams::MASK)
      expect(op.result['federation_peer_id']).to eq('peer-42')
    end

    it 'does not disclose the secret on a subsequent read of the same approval' do
      approve_via_rest!

      get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      # Positive control: the read really rendered the executed operation, so
      # the absence above is not the absence of a payload.
      expect(json_response_data.dig('deferred_operation', 'status')).to eq('completed')
      expect(response.body).not_to include(minted_secret)
    end

    it 'does not disclose the secret to a second decision on the same request' do
      approve_via_rest!
      approve_via_rest!

      expect(response).to have_http_status(422)
      expect(response.body).not_to include(minted_secret)
    end
  end

  describe 'POST /api/v1/ai/autonomy/approvals/:id/reject' do
    before { enable_governance.call }

    it 'reveals nothing — the executor never ran' do
      post "/api/v1/ai/autonomy/approvals/#{approval_request.id}/reject", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response_data).not_to have_key('revealed_result')
      expect(deferred.reload.status).to eq('rejected')
      expect(response.body).not_to include(minted_secret)
    end
  end

  describe 'Ai::DeferredOperation reveal-once slot' do
    it 'hands the raw executor return to the first reader and nothing to the second' do
      deferred.execute_now!

      expect(deferred.take_revealed_result![:acceptance_token_plaintext]).to eq(minted_secret)
      expect(deferred.take_revealed_result!).to be_nil
    end

    it 'is unreachable from a re-loaded row (nothing was stored)' do
      deferred.execute_now!

      expect(::Ai::DeferredOperation.find(deferred.id).take_revealed_result!).to be_nil
    end
  end

  describe 'Ai::ApprovalRequest reveal-once slot' do
    it 'carries the reveal from the source instance the decision cascade executed' do
      approval_request.approve!

      expect(approval_request.take_revealed_result![:acceptance_token_plaintext]).to eq(minted_secret)
      expect(approval_request.take_revealed_result!).to be_nil
    end

    it 'is unreachable from a re-loaded row (nothing was stored)' do
      approval_request.approve!

      expect(::Ai::ApprovalRequest.find(approval_request.id).take_revealed_result!).to be_nil
    end

    it 'reveals nothing on rejection' do
      approval_request.reject!

      expect(approval_request.take_revealed_result!).to be_nil
      expect(deferred.reload.status).to eq('rejected')
    end
  end

  # The OTHER human surface that resolves an approval and therefore runs the
  # same executors. Ai::GovernanceService#process_approval_decision returns the
  # object the cascade fired on (#reload returns self), which is what makes the
  # in-memory slot reachable from a second controller.
  describe 'POST /api/v1/ai/governance/approval_requests/:id/decide' do
    let(:governor) do
      create(:user, account: account,
                    permissions: %w[ai.agents.read ai.governance.read ai.governance.manage])
    end
    let(:governance_headers) { auth_headers_for(governor) }

    it 'carries the minted secret on the governance decision response' do
      post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
           params: { decision: 'approved' }, headers: governance_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response_data.dig('approval_request', 'revealed_result', 'acceptance_token_plaintext'))
        .to eq(minted_secret)
    end

    it 'still redacts at rest and reveals nothing on a rejection' do
      post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
           params: { decision: 'rejected' }, headers: governance_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response_data['approval_request']).not_to have_key('revealed_result')
      expect(deferred.reload.status).to eq('rejected')
    end
  end

  # Not an oversight — a decision, pinned. Ai::AgentToolBridgeService persists a
  # 200-byte preview of every tool return to ai_messages.processing_metadata and
  # forwards the full JSON to the model provider as a role:"tool" message, so
  # revealing minted key material through an MCP tool return would create the
  # durable off-platform copy the handoff exists to avoid. A change that starts
  # revealing here should red this and read the comment at the call site.
  describe 'Ai::Tools::AgentAutonomyTool#approve_deferred_operation' do
    let(:tool) { ::Ai::Tools::AgentAutonomyTool.new(account: account, user: approver) }

    before { enable_governance.call }

    it 'runs the executor but does NOT carry the reveal onto the MCP tool return' do
      result = tool.send(:approve_deferred_operation, { deferred_operation_id: deferred.id })

      expect(result[:success]).to be(true)
      expect(deferred.reload.status).to eq('completed')
      expect(result).not_to have_key(:revealed_result)
      expect(result.to_json).not_to include(minted_secret)
    end
  end

  # The reviewer's point, made mechanical: "nothing was stored" cannot be shown
  # by a fresh instance answering nil — that is true by construction. It has to
  # be asserted against the COLUMNS of both rows after a full reveal has been
  # taken.
  describe 'nothing durable holds the mint after it has been revealed' do
    before { enable_governance.call }

    it 'leaves no attribute of either row carrying the plaintext' do
      approve_via_rest!
      expect(json_response_data.dig('revealed_result', 'acceptance_token_plaintext'))
        .to eq(minted_secret) # premise: the reveal really happened

      expect(::Ai::DeferredOperation.find(deferred.id).attributes.to_json).not_to include(minted_secret)
      expect(::Ai::ApprovalRequest.find(approval_request.id).attributes.to_json).not_to include(minted_secret)
      expect(::Ai::ApprovalDecision.where(approval_request_id: approval_request.id).to_json)
        .not_to include(minted_secret)
    end
  end

  describe 'the auto-approve path is unchanged' do
    it 'still returns the raw mint inline and still redacts at rest' do
      ::Ai::InterventionPolicy
        .where(account_id: account.id, action_category: 'test.minting_action')
        .update_all(policy: 'auto_approve')

      result = ::Ai::AutonomyGate.evaluate(
        action_category: 'test.minting_action',
        executor_class: 'MintingSpecExecutor',
        params: { attributes: { remote_instance_url: 'https://other.example' } },
        account: account,
        requested_by: approver,
        description: 'Propose federation with https://other.example'
      )

      expect(result.decision).to eq(:proceed)
      expect(result.result[:acceptance_token_plaintext]).to eq(minted_secret)
      expect(result.deferred_operation.reload.result['acceptance_token_plaintext'])
        .to eq(::Ai::SensitiveParams::MASK)
    end
  end
end

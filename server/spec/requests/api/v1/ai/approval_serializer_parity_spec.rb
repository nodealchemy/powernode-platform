# frozen_string_literal: true

require 'rails_helper'

# IMP-550e44e24220 — the two approval read surfaces serialize the same
# Ai::ApprovalRequest through independently maintained code:
#
#   GET /api/v1/ai/governance/approval_requests/:id
#       → Api::V1::Ai::GovernanceController#approval_request_json
#   GET /api/v1/ai/autonomy/approvals/:id
#       → Ai::AutonomyApprovalActions#serialize_approval_request
#
# Parity between them was maintained by "in parity with" comments only. Two
# changes had to be hand-applied to both copies (the request_data redaction and
# the execution_status/execution_error pair), which is exactly the drift vector
# the redaction work exists to close: a future redaction rule applied to one
# copy leaves the other endpoint serving secret-bearing request_data to an
# audience defined by the approval permissions.
#
# WHY THIS GUARD IS SHAPED THE WAY IT IS.
#
# The two payloads are NOT identical and are not supposed to become identical —
# each endpoint keeps fields the other has no use for (governance has
# updated_at; autonomy has the agent_*/action_* denormalisations, the deferred
# operation, and current_step_can_approve). What must not drift is the SHARED
# CORE both surfaces emit, which is where request_data lives.
#
# So the oracle is DERIVED, not hand-listed: it reads
# Ai::ApprovalRequestSerialization::CORE_KEYS — the single definition both
# controllers now build from — and asserts the two responses agree on every one
# of them. A hand-listed oracle would silently walk past the fourteenth field
# somebody adds to the shared core.
#
# DIVERGENT_KEYS is the deliberate exception list. Both surfaces emit these,
# but with intentionally different shapes, so they cannot be value-compared.
# Requiring new divergences to be declared here is the point: the intersection
# assertion below fails when a key starts appearing on both surfaces without
# being either shared-and-equal or explicitly declared divergent.
RSpec.describe 'Approval serializer parity across read surfaces', type: :request do
  let(:account) { create(:account) }

  # The same audience the secret-exposure spec uses: the plainest AI-read
  # permissions already reach both payloads.
  let(:reader) do
    create(:user, account: account, permissions: %w[ai.agents.read ai.governance.read])
  end
  let(:headers) { auth_headers_for(reader) }

  # The factory's default request_data ({ reason: ... }) carries nothing
  # Ai::SensitiveParams redacts, which would make filtered and unfiltered output
  # byte-identical — a guard built on it could not detect the exact drift it
  # exists to prevent. `acceptance_token` matches the `token` pattern and is not
  # on the exact-match safe list, so the two differ observably.
  let(:plaintext) { 'ACCEPTANCE-TOKEN-PLAINTEXT' }
  let!(:approval_request) do
    create(:ai_approval_request, account: account, status: 'pending',
           request_data: { 'reason' => 'Deployment approval required',
                           'acceptance_token' => plaintext })
  end

  # Emitted by both surfaces, deliberately different shapes:
  #   approval_chain — governance renders the full chain (trigger_type,
  #     trigger_conditions, usage_count, ...); autonomy renders the operational
  #     subset plus timeout_action, which governance does not carry.
  #   decisions      — governance includes `conditions` and a nested approver
  #     object (name/email); autonomy includes a bare approver_id.
  #   step_statuses  — governance carries it in the LIST payload too; autonomy
  #     carries total_steps there instead and only adds step_statuses on detail.
  DIVERGENT_KEYS = %w[approval_chain decisions step_statuses].freeze

  def governance_detail
    get "/api/v1/ai/governance/approval_requests/#{approval_request.id}",
        headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).dig('data', 'approval_request')
  end

  def autonomy_detail
    get "/api/v1/ai/autonomy/approvals/#{approval_request.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']
  end

  describe 'the shared core' do
    it 'is defined in exactly one place' do
      expect(defined?(::Ai::ApprovalRequestSerialization::CORE_KEYS))
        .to eq('constant'),
          'Both surfaces still build their own core payload — there is no single ' \
          'definition for this spec to derive its oracle from.'

      expect(::Ai::ApprovalRequestSerialization::CORE_KEYS).to include(:request_data)
    end

    it 'is emitted identically by both read surfaces' do
      gov = governance_detail
      aut = autonomy_detail

      ::Ai::ApprovalRequestSerialization::CORE_KEYS.each do |key|
        k = key.to_s
        expect(gov).to have_key(k), "governance payload is missing core key #{k}"
        expect(aut).to have_key(k), "autonomy payload is missing core key #{k}"
        expect(gov[k]).to eq(aut[k]),
                          "core key #{k} has drifted between the two surfaces: " \
                          "governance=#{gov[k].inspect} autonomy=#{aut[k].inspect}"
      end
    end

    # The drift vector that motivated the extraction, stated directly rather
    # than inferred from the core comparison above.
    it 'filters request_data on both surfaces through the same call' do
      expect(::Ai::ApprovalRequestSerialization::CORE_KEYS).to include(:request_data)

      gov = governance_detail
      aut = autonomy_detail

      expect(gov['request_data']).to eq(aut['request_data'])

      # Equality alone would still pass if BOTH surfaces stopped filtering, so
      # assert the redaction itself. This is what makes the shared core worth
      # extracting: one definition, one place the mask can be lost.
      expect(gov.dig('request_data', 'acceptance_token')).to eq('[FILTERED]')
      expect(aut.dig('request_data', 'acceptance_token')).to eq('[FILTERED]')
      expect(response.body).not_to include(plaintext)
    end
  end

  describe 'every key both surfaces emit' do
    it 'is either shared-and-equal or explicitly declared divergent' do
      gov = governance_detail
      aut = autonomy_detail

      overlap = gov.keys & aut.keys
      accounted = ::Ai::ApprovalRequestSerialization::CORE_KEYS.map(&:to_s) + DIVERGENT_KEYS

      undeclared = overlap - accounted
      expect(undeclared).to be_empty,
                            "these keys appear on BOTH surfaces but are neither part of the " \
                            "shared core nor declared divergent: #{undeclared.inspect}. Add them " \
                            "to the shared core (preferred) or to DIVERGENT_KEYS with a reason."
    end
  end

  # Byte-identity regression pins. The extraction must not change what either
  # endpoint returns; these record the exact top-level key sets observed on the
  # pre-refactor code, so a field silently lost or gained fails here.
  describe 'response shape is unchanged by the extraction' do
    it 'pins the governance detail key set' do
      expect(governance_detail.keys.sort).to eq(
        %w[
          approval_chain completed_at created_at current_step decisions description
          execution_error execution_status expires_at id request_data request_id
          source_id source_type status step_statuses updated_at
        ]
      )
    end

    it 'pins the autonomy detail key set' do
      expect(autonomy_detail.keys.sort).to eq(
        %w[
          action_category action_type agent_id agent_name approval_chain completed_at
          created_at current_step current_step_can_approve decisions deferred_operation
          description execution_error execution_status expires_at id request_data
          request_id requested_by_id source_id source_type status step_statuses total_steps
        ]
      )
    end

    # The LIST payloads matter at least as much as the detail ones: they are
    # where Ai::SensitiveParams.batch wraps the whole page, so a core field
    # dropped here is dropped for every row at once.
    it 'pins the governance list key set' do
      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body).dig('data', 'approval_requests')

      expect(rows).to be_present, 'no rows to pin — the fixture stopped being listed'
      expect(rows.first.keys.sort).to eq(
        %w[
          approval_chain completed_at created_at current_step description
          execution_error execution_status expires_at id request_data request_id
          source_id source_type status step_statuses
        ]
      )
    end

    # Ai::Autonomy::ApprovalWorkflowService#pending_approvals opens with
    # `return [] unless governance_enabled?`, a capability gate that is FALSE in
    # core mode — so this list surface serves nothing at all unless a governance
    # extension is loaded. Enabling it here is the point rather than a
    # workaround: the deployment where two approval serializers can drift apart
    # is precisely the one where governance is present, and pinning the payload
    # against the dead core-mode branch would pin nothing.
    it 'pins the autonomy list key set' do
      allow(::Ai::Autonomy::ApprovalWorkflowService).to receive(:governance_enabled?).and_return(true)

      get '/api/v1/ai/autonomy/approvals', headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      rows = JSON.parse(response.body)['data']

      expect(rows).to be_present, 'no rows to pin — the fixture stopped being listed'
      expect(rows.first.keys.sort).to eq(
        %w[
          action_category action_type agent_id agent_name completed_at created_at
          current_step description execution_error execution_status expires_at id
          request_data request_id requested_by_id source_id source_type status total_steps
        ]
      )
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Governance', type: :request do
  let(:account) { create(:account) }
  # Holds both the governance READ gate and the coarse manage gate so the
  # existing read+write coverage exercises the happy path. Authorization is
  # asserted separately in the "authorization" describe block below.
  let(:user) { create(:user, account: account, permissions: %w[ai.governance.read ai.manage]) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/ai/governance/policies' do
    let!(:policy1) { create(:ai_compliance_policy, account: account, policy_type: 'retention') }
    let!(:policy2) { create(:ai_compliance_policy, account: account, policy_type: 'data_access') }

    it 'returns list of policies' do
      get '/api/v1/ai/governance/policies', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['policies']).to be_an(Array)
      expect(data).to have_key('pagination')
    end

    it 'filters by policy type' do
      get "/api/v1/ai/governance/policies?type=retention", headers: headers, as: :json

      expect_success_response
    end

    it 'filters by status' do
      get "/api/v1/ai/governance/policies?status=active", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/ai/governance/policies' do
    let(:policy_params) do
      {
        name: 'New Policy',
        policy_type: 'retention',
        enforcement_level: 'strict',
        conditions: { retention_days: 90 },
        actions: { delete_after: 90 }
      }
    end

    it 'creates a new policy' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:create_policy)
        .and_return(create(:ai_compliance_policy, account: account))

      post '/api/v1/ai/governance/policies', params: policy_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data['policy']).to be_present
    end
  end

  describe 'PUT /api/v1/ai/governance/policies/:id/activate' do
    let(:policy) { create(:ai_compliance_policy, account: account, status: 'draft') }

    it 'activates the policy' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:activate_policy)
        .and_return({ policy: policy })

      put "/api/v1/ai/governance/policies/#{policy.id}/activate", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['policy']).to be_present
    end
  end

  describe 'POST /api/v1/ai/governance/policies/evaluate' do
    let(:context_params) { { context: { action: 'data_access', resource: 'sensitive_data' } } }

    it 'evaluates policies against context' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:evaluate_policies)
        .and_return({ allowed: true, results: [] })

      post '/api/v1/ai/governance/policies/evaluate', params: context_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('allowed')
      expect(data).to have_key('results')
    end
  end

  describe 'GET /api/v1/ai/governance/violations' do
    let!(:violation) { create(:ai_policy_violation, account: account) }

    it 'returns list of violations' do
      get '/api/v1/ai/governance/violations', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['violations']).to be_an(Array)
    end

    it 'filters by status' do
      get "/api/v1/ai/governance/violations?status=pending", headers: headers, as: :json

      expect_success_response
    end

    it 'filters by severity' do
      get "/api/v1/ai/governance/violations?severity=high", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'PUT /api/v1/ai/governance/violations/:id/acknowledge' do
    let(:violation) { create(:ai_policy_violation, account: account, status: 'open') }

    it 'acknowledges the violation' do
      allow_any_instance_of(Ai::PolicyViolation).to receive(:acknowledge!).and_return(true)

      put "/api/v1/ai/governance/violations/#{violation.id}/acknowledge", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['violation']).to be_present
    end
  end

  describe 'PUT /api/v1/ai/governance/violations/:id/resolve' do
    let(:violation) { create(:ai_policy_violation, account: account, status: 'acknowledged') }

    it 'resolves the violation' do
      allow_any_instance_of(Ai::PolicyViolation).to receive(:resolve!).and_return(true)

      put "/api/v1/ai/governance/violations/#{violation.id}/resolve",
          params: { notes: 'Resolved', action: 'corrected' },
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/ai/governance/approval_chains' do
    let!(:chain) { create(:ai_approval_chain, account: account) }

    it 'returns list of approval chains' do
      get '/api/v1/ai/governance/approval_chains', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['approval_chains']).to be_an(Array)
    end
  end

  describe 'POST /api/v1/ai/governance/approval_chains' do
    let(:chain_params) do
      {
        name: 'New Approval Chain',
        trigger_type: 'manual',
        steps: [ { order: 1, approver_role: 'manager' } ]
      }
    end

    it 'creates a new approval chain' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:create_approval_chain)
        .and_return(create(:ai_approval_chain, account: account))

      post '/api/v1/ai/governance/approval_chains', params: chain_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data['approval_chain']).to be_present
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests' do
    let!(:approval_req) { create(:ai_approval_request, account: account) }

    it 'returns list of approval requests' do
      get '/api/v1/ai/governance/approval_requests', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['approval_requests']).to be_an(Array)
    end

    it 'filters by status' do
      get "/api/v1/ai/governance/approval_requests?status=pending", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests/pending' do
    let!(:pending_request) { create(:ai_approval_request, account: account, status: 'pending') }

    it 'returns pending approval requests' do
      get '/api/v1/ai/governance/approval_requests/pending', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['approval_requests']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/ai/governance/approval_requests/:id' do
    let!(:approval_req) { create(:ai_approval_request, account: account) }

    it 'returns the approval request with chain and decisions' do
      get "/api/v1/ai/governance/approval_requests/#{approval_req.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['approval_request']).to be_present
      expect(data['approval_request']['id']).to eq(approval_req.id)
      expect(data['approval_request']).to have_key('decisions')
      expect(data['approval_request']['decisions']).to be_an(Array)
      expect(data['approval_request']['approval_chain']['id']).to eq(approval_req.approval_chain_id)
    end

    it 'includes recorded decisions with approver info' do
      approver = create(:user, account: account)
      create(:ai_approval_decision, approval_request: approval_req, approver: approver,
                                    step_number: 0, decision: 'approved', comments: 'LGTM')

      get "/api/v1/ai/governance/approval_requests/#{approval_req.id}", headers: headers, as: :json

      expect_success_response
      decisions = json_response_data['approval_request']['decisions']
      expect(decisions.size).to eq(1)
      expect(decisions.first['decision']).to eq('approved')
      expect(decisions.first['approver']['id']).to eq(approver.id)
    end

    it 'returns 404 for an unknown id' do
      get "/api/v1/ai/governance/approval_requests/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response('Approval request not found', 404)
    end

    it 'does not expose approval requests from another account' do
      other = create(:ai_approval_request, account: create(:account))

      get "/api/v1/ai/governance/approval_requests/#{other.id}", headers: headers, as: :json

      expect_error_response('Approval request not found', 404)
    end

    it 'requires authentication' do
      get "/api/v1/ai/governance/approval_requests/#{approval_req.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/ai/governance/approval_requests/:id/decide' do
    let(:approval_request) { create(:ai_approval_request, account: account, status: 'pending') }

    it 'approves the request' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:process_approval_decision)
        .and_return({ success: true, request: approval_request })

      post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
           params: { decision: 'approve', comments: 'Approved' },
           headers: headers,
           as: :json

      expect_success_response
      data = json_response_data
      expect(data['approval_request']).to be_present
    end

    it 'rejects the request' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:process_approval_decision)
        .and_return({ success: true, request: approval_request })

      post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
           params: { decision: 'reject', comments: 'Rejected' },
           headers: headers,
           as: :json

      expect_success_response
    end

    it 'returns error when decision fails' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:process_approval_decision)
        .and_return({ success: false, error: 'Decision failed' })

      post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
           params: { decision: 'approve' },
           headers: headers,
           as: :json

      expect_error_response('Decision failed', 422)
    end
  end

  describe 'GET /api/v1/ai/governance/classifications' do
    let!(:classification) { create(:ai_data_classification, account: account) }

    it 'returns list of classifications' do
      get '/api/v1/ai/governance/classifications', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['classifications']).to be_an(Array)
    end
  end

  describe 'POST /api/v1/ai/governance/classifications' do
    let(:classification_params) do
      {
        name: 'PII',
        classification_level: 'high',
        detection_patterns: [ 'ssn', 'email' ],
        handling_requirements: { encrypt: true }
      }
    end

    it 'creates a new classification' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:create_classification)
        .and_return(create(:ai_data_classification, account: account))

      post '/api/v1/ai/governance/classifications', params: classification_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data['classification']).to be_present
    end
  end

  describe 'POST /api/v1/ai/governance/scan' do
    let(:scan_params) { { text: 'Test data with email@example.com' } }

    it 'scans for sensitive data' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:scan_for_sensitive_data)
        .and_return({ has_sensitive_data: true, detections: [] })

      post '/api/v1/ai/governance/scan', params: scan_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('has_sensitive_data')
      expect(data).to have_key('detections')
    end
  end

  describe 'POST /api/v1/ai/governance/mask' do
    let(:mask_params) { { text: 'Sensitive data: email@example.com' } }

    it 'masks sensitive data' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:mask_sensitive_data)
        .and_return('Sensitive data: ***')

      post '/api/v1/ai/governance/mask', params: mask_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['masked_text']).to be_present
    end
  end

  describe 'GET /api/v1/ai/governance/reports' do
    let!(:report) { create(:ai_compliance_report, account: account) }

    it 'returns list of reports' do
      get '/api/v1/ai/governance/reports', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['reports']).to be_an(Array)
    end
  end

  describe 'POST /api/v1/ai/governance/reports' do
    let(:report_params) do
      {
        report_type: 'compliance',
        period_start: 30.days.ago.to_s,
        period_end: Time.current.to_s
      }
    end

    it 'generates a compliance report' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:generate_report)
        .and_return(create(:ai_compliance_report, account: account))

      post '/api/v1/ai/governance/reports', params: report_params, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data['report']).to be_present
    end
  end

  describe 'GET /api/v1/ai/governance/summary' do
    it 'returns compliance summary' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:get_compliance_summary)
        .and_return({ total_policies: 5, active_policies: 3, violations: 2 })

      get '/api/v1/ai/governance/summary', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['summary']).to be_present
    end

    it 'accepts date range parameters' do
      allow_any_instance_of(Ai::GovernanceService).to receive(:get_compliance_summary)
        .and_return({ total_policies: 5, active_policies: 3, violations: 2 })

      get "/api/v1/ai/governance/summary?start_date=#{30.days.ago}&end_date=#{Time.current}", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/ai/governance/audit_log' do
    let!(:entry) { create(:ai_compliance_audit_entry, account: account) }

    it 'returns audit log entries' do
      get '/api/v1/ai/governance/audit_log', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['entries']).to be_an(Array)
    end

    it 'filters by action type' do
      get "/api/v1/ai/governance/audit_log?action_type=policy_update", headers: headers, as: :json

      expect_success_response
    end

    it 'filters by resource type' do
      get "/api/v1/ai/governance/audit_log?resource_type=policy", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'authorization' do
    # An authenticated user holding NEITHER the governance read perm nor the
    # coarse manage perm. Before the gate was added, every governance action
    # was reachable by any authenticated user (decide approvals, create/activate
    # policies, resolve violations, read the audit log, ...).
    let(:unprivileged) { create(:user, account: account, permissions: []) }
    let(:unprivileged_headers) { auth_headers_for(unprivileged) }

    context 'without the governance read permission' do
      it 'forbids reading the audit log' do
        get '/api/v1/ai/governance/audit_log', headers: unprivileged_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'forbids listing policies' do
        get '/api/v1/ai/governance/policies', headers: unprivileged_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without the manage permission' do
      it 'forbids creating a policy' do
        post '/api/v1/ai/governance/policies',
             params: { name: 'X', policy_type: 'retention', enforcement_level: 'strict' },
             headers: unprivileged_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'forbids deciding an approval request' do
        approval_request = create(:ai_approval_request, account: account, status: 'pending')
        post "/api/v1/ai/governance/approval_requests/#{approval_request.id}/decide",
             params: { decision: 'approve' }, headers: unprivileged_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end

      it 'forbids resolving a violation' do
        violation = create(:ai_policy_violation, account: account, status: 'acknowledged')
        put "/api/v1/ai/governance/violations/#{violation.id}/resolve",
            params: { notes: 'x' }, headers: unprivileged_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with the governance read permission' do
      let(:reader) { create(:user, account: account, permissions: %w[ai.governance.read]) }

      it 'permits reading the audit log' do
        create(:ai_compliance_audit_entry, account: account)
        get '/api/v1/ai/governance/audit_log', headers: auth_headers_for(reader), as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'still forbids a write (manage-gated) action' do
        post '/api/v1/ai/governance/policies',
             params: { name: 'X', policy_type: 'retention', enforcement_level: 'strict' },
             headers: auth_headers_for(reader), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with the manage permission' do
      let(:manager) { create(:user, account: account, permissions: %w[ai.manage]) }

      it 'permits creating a policy (reaches the service, not 403)' do
        allow_any_instance_of(Ai::GovernanceService).to receive(:create_policy)
          .and_return(create(:ai_compliance_policy, account: account))

        post '/api/v1/ai/governance/policies',
             params: { name: 'X', policy_type: 'retention', enforcement_level: 'strict' },
             headers: auth_headers_for(manager), as: :json
        expect(response).not_to have_http_status(:forbidden)
        expect(response).to have_http_status(:created)
      end
    end
  end
end

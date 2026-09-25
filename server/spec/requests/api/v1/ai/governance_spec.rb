# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Governance', type: :request do
  let(:account) { create(:account) }
  # Holds the dedicated governance READ + MANAGE gates so the existing read+write
  # coverage exercises the happy path. Authorization (incl. that the coarse
  # ai.manage no longer grants governance writes) is asserted separately in the
  # "authorization" describe block below.
  let(:user) { create(:user, account: account, permissions: %w[ai.governance.read ai.governance.manage]) }
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

    context 'with the dedicated governance manage permission' do
      let(:manager) { create(:user, account: account, permissions: %w[ai.governance.read ai.governance.manage]) }

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

    # Governance writes are DECOUPLED from the coarse manage-all-AI gate: holding
    # only ai.manage (e.g. an AI operator without governance authority) must no
    # longer be able to create policies or resolve violations.
    context 'with only the coarse ai.manage permission (decoupled from governance writes)' do
      let(:coarse) { create(:user, account: account, permissions: %w[ai.manage]) }

      it 'forbids creating a policy' do
        post '/api/v1/ai/governance/policies',
             params: { name: 'X', policy_type: 'retention', enforcement_level: 'strict' },
             headers: auth_headers_for(coarse), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

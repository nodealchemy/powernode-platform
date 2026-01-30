# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::RemediationPlans', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write']) }
  let(:admin_user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write', 'supply_chain.admin']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['supply_chain.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/supply_chain/remediation_plans' do
    let!(:plan1) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'draft',
             plan_type: 'manual')
    end
    let!(:plan2) do
      create(:supply_chain_remediation_plan, :approved,
             account: account,
             created_by: user)
    end
    let!(:other_plan) { create(:supply_chain_remediation_plan, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of remediation plans for current account' do
        get '/api/v1/supply_chain/remediation_plans', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plans']).to be_an(Array)
        expect(data['remediation_plans'].length).to eq(2)
        expect(data['remediation_plans'].none? { |p| p['id'] == other_plan.id }).to be true
        expect(json_response['meta']).to have_key('total_count')
      end

      it 'filters by status' do
        get '/api/v1/supply_chain/remediation_plans',
            params: { status: 'draft' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['remediation_plans'].length).to eq(1)
        expect(data['remediation_plans'].first['status']).to eq('draft')
      end

      it 'filters by plan_type' do
        get '/api/v1/supply_chain/remediation_plans',
            params: { plan_type: 'manual' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['remediation_plans'].all? { |p| p['plan_type'] == 'manual' }).to be true
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/remediation_plans', headers: unauthorized_headers, as: :json

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/remediation_plans', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/remediation_plans/:id' do
    let(:plan) do
      create(:supply_chain_remediation_plan, :with_vulnerabilities, :with_upgrades,
             account: account,
             created_by: user)
    end
    let(:other_plan) { create(:supply_chain_remediation_plan, account: other_account) }

    context 'with proper permissions' do
      it 'returns remediation plan details' do
        get "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']['id']).to eq(plan.id)
        expect(data['remediation_plan']['plan_type']).to eq(plan.plan_type)
        expect(data['remediation_plan']['status']).to eq(plan.status)
        expect(data['remediation_plan']['created_by']).to be_present
        # Details included in show
        expect(data['remediation_plan']['target_vulnerabilities']).to be_present
        expect(data['remediation_plan']['upgrade_recommendations']).to be_present
      end

      it 'returns not found for non-existent plan' do
        get "/api/v1/supply_chain/remediation_plans/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Remediation plan not found', 404)
      end
    end

    context 'accessing plan from different account' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/remediation_plans/#{other_plan.id}", headers: headers, as: :json

        expect_error_response('Remediation plan not found', 404)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/remediation_plans' do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let(:valid_params) do
      {
        remediation_plan: {
          plan_type: 'manual',
          sbom_id: sbom.id,
          confidence_score: 0.85,
          auto_executable: false,
          target_vulnerabilities: [{ 'vulnerability_id' => 'CVE-2024-12345', 'severity' => 'critical' }],
          upgrade_recommendations: [{ 'package_name' => 'lodash', 'target_version' => '4.17.21' }]
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new remediation plan' do
        expect {
          post '/api/v1/supply_chain/remediation_plans', params: valid_params, headers: headers, as: :json
        }.to change { account.supply_chain_remediation_plans.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['remediation_plan']['plan_type']).to eq('manual')
        expect(data['remediation_plan']['status']).to eq('draft')
        expect(account.supply_chain_remediation_plans.last.created_by).to eq(user)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { remediation_plan: { plan_type: nil } }

        post '/api/v1/supply_chain/remediation_plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post '/api/v1/supply_chain/remediation_plans', params: valid_params, headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'PATCH /api/v1/supply_chain/remediation_plans/:id' do
    let(:plan) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'draft')
    end
    let(:update_params) do
      {
        remediation_plan: {
          confidence_score: 0.95,
          auto_executable: true
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the remediation plan' do
        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']['confidence_score'].to_f).to eq(0.95)
        expect(data['remediation_plan']['auto_executable']).to eq(true)
      end

      it 'returns error when plan is not editable (not draft)' do
        plan.update!(status: 'approved')

        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect_error_response('Plan cannot be edited in current status', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: update_params, headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'DELETE /api/v1/supply_chain/remediation_plans/:id' do
    let!(:plan) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'draft')
    end

    context 'with proper permissions' do
      it 'deletes the remediation plan' do
        expect {
          delete "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: headers, as: :json
        }.to change { account.supply_chain_remediation_plans.count }.by(-1)

        expect_success_response
      end

      it 'returns error when plan is not deletable (not draft)' do
        plan.update!(status: 'approved')

        delete "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: headers, as: :json

        expect_error_response('Plan cannot be deleted in current status', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        delete "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/approve' do
    let(:plan) do
      create(:supply_chain_remediation_plan, :pending_review,
             account: account,
             created_by: user)
    end

    context 'with admin permissions' do
      it 'approves the remediation plan' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/approve",
             params: { comment: 'Approved for production' },
             headers: admin_headers,
             as: :json

        expect_success_response
      end

      it 'returns error when plan is not pending review' do
        plan.update!(status: 'draft')

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/approve",
             headers: admin_headers,
             as: :json

        expect_error_response('Plan is not pending approval', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/approve",
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/reject' do
    let(:plan) do
      create(:supply_chain_remediation_plan, :pending_review,
             account: account,
             created_by: user)
    end

    context 'with admin permissions' do
      it 'rejects the remediation plan' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             params: { reason: 'Not suitable for production' },
             headers: admin_headers,
             as: :json

        expect_success_response
      end

      it 'returns error when plan is not pending review' do
        plan.update!(status: 'draft')

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             params: { reason: 'Test' },
             headers: admin_headers,
             as: :json

        expect_error_response('Plan is not pending approval', 422)
      end

      it 'returns error when reason is missing' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             headers: admin_headers,
             as: :json

        expect_error_response('Rejection reason is required', 422)
      end
    end

    context 'without supply_chain.admin permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             params: { reason: 'Test' },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions for supply chain administration', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/execute' do
    let(:plan) do
      create(:supply_chain_remediation_plan, :approved,
             account: account,
             created_by: user)
    end

    context 'with proper permissions' do
      it 'starts remediation execution' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/execute",
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'returns error when plan is not approved' do
        plan.update!(status: 'draft')

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/execute",
             headers: headers,
             as: :json

        expect_error_response('Plan must be approved before execution', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/execute",
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/generate_pr' do
    let(:plan) do
      create(:supply_chain_remediation_plan, :approved,
             account: account,
             created_by: user,
             target_vulnerabilities: [{ 'vulnerability_id' => 'CVE-2024-1234', 'severity' => 'critical' }],
             upgrade_recommendations: [{ 'package_name' => 'lodash', 'current_version' => '4.17.20', 'target_version' => '4.17.21' }])
    end
    let(:repository) { create(:devops_repository, account: account) }
    let(:pr_service_result) do
      {
        success: true,
        pr_url: 'https://github.com/org/repo/pull/123',
        pr_number: 123,
        branch_name: 'remediation/abc12345-20260129'
      }
    end

    before do
      allow_any_instance_of(::SupplyChain::RemediationPrService).to receive(:generate_pr).and_return(pr_service_result)
    end

    context 'with proper permissions and approved plan' do
      before do
        # Associate repository with plan via metadata
        plan.update!(metadata: { 'repository_id' => repository.id })
      end

      it 'generates a pull request' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['pr_url']).to eq('https://github.com/org/repo/pull/123')
        expect(data['pr_number']).to eq(123)
        expect(data['branch_name']).to be_present
      end

      it 'includes updated remediation plan in response' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        data = json_response_data
        expect(data['remediation_plan']).to be_present
      end
    end

    context 'when plan is not approved' do
      let(:draft_plan) do
        create(:supply_chain_remediation_plan,
               account: account,
               created_by: user,
               status: 'draft')
      end

      it 'returns error' do
        post "/api/v1/supply_chain/remediation_plans/#{draft_plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('Plan must be approved before generating a PR', 422)
      end
    end

    context 'when PR has already been generated' do
      before do
        plan.update!(generated_pr_url: 'https://github.com/org/repo/pull/100')
      end

      it 'returns error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('PR has already been generated for this plan', 422)
      end
    end

    context 'when no repository is associated' do
      it 'returns error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('No repository associated with this remediation plan', 422)
      end
    end

    context 'when PR generation fails' do
      let(:failed_result) { { success: false, error: 'GitHub API error: rate limited' } }

      before do
        plan.update!(metadata: { 'repository_id' => repository.id })
        allow_any_instance_of(::SupplyChain::RemediationPrService).to receive(:generate_pr).and_return(failed_result)
      end

      it 'returns error message' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('GitHub API error: rate limited', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end
end

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
    let!(:vulnerability) { create(:supply_chain_vulnerability, account: account) }
    let!(:plan1) do
      create(:supply_chain_remediation_plan,
             account: account,
             vulnerability: vulnerability,
             created_by: user,
             status: 'draft',
             priority: 'high')
    end
    let!(:plan2) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'approved',
             priority: 'medium')
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
        expect(data['meta']).to have_key('total')
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

      it 'filters by priority' do
        get '/api/v1/supply_chain/remediation_plans',
            params: { priority: 'high' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['remediation_plans'].all? { |p| p['priority'] == 'high' }).to be true
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
    let(:vulnerability) { create(:supply_chain_vulnerability, account: account) }
    let(:plan) do
      create(:supply_chain_remediation_plan,
             account: account,
             vulnerability: vulnerability,
             created_by: user,
             steps: ['Step 1', 'Step 2'],
             affected_components: [{ 'name' => 'test-package', 'version' => '1.0.0' }])
    end
    let(:other_plan) { create(:supply_chain_remediation_plan, account: other_account) }

    context 'with proper permissions' do
      it 'returns remediation plan details' do
        get "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']).to include(
          'id' => plan.id,
          'title' => plan.title,
          'status' => plan.status,
          'priority' => plan.priority
        )
        expect(data['remediation_plan']['created_by']).to be_present
        expect(data['remediation_plan']['steps']).to be_present
        expect(data['remediation_plan']['affected_components']).to be_present
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
    let(:vulnerability) { create(:supply_chain_vulnerability, account: account) }
    let(:valid_params) do
      {
        remediation_plan: {
          title: 'Fix Critical Vulnerability',
          description: 'Upgrade vulnerable package',
          priority: 'critical',
          vulnerability_id: vulnerability.id,
          target_version: '2.0.0',
          remediation_type: 'upgrade',
          deadline: 7.days.from_now.to_date,
          steps: ['Update package.json', 'Run npm install', 'Test application'],
          affected_components: [{ 'name' => 'lodash', 'version' => '4.17.0' }]
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
        expect(data['remediation_plan']).to include(
          'title' => 'Fix Critical Vulnerability',
          'status' => 'draft',
          'priority' => 'critical'
        )
        expect(account.supply_chain_remediation_plans.last.created_by).to eq(user)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(remediation_plan: { title: nil })

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
          title: 'Updated Title',
          description: 'Updated description',
          priority: 'high'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the remediation plan' do
        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']['title']).to eq('Updated Title')
        expect(data['remediation_plan']['description']).to eq('Updated description')
        expect(data['remediation_plan']['priority']).to eq('high')
      end

      it 'returns error when plan is not editable' do
        plan.update!(status: 'executing')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:editable?).and_return(false)

        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect_error_response('Plan cannot be edited in current status', 422)
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { remediation_plan: { priority: 'invalid' } }

        patch "/api/v1/supply_chain/remediation_plans/#{plan.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
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
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:deletable?).and_return(true)

        expect {
          delete "/api/v1/supply_chain/remediation_plans/#{plan.id}", headers: headers, as: :json
        }.to change { account.supply_chain_remediation_plans.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Remediation plan deleted')
      end

      it 'returns error when plan is not deletable' do
        plan.update!(status: 'approved')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:deletable?).and_return(false)

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

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/generate_pr' do
    let(:plan) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'approved')
    end

    context 'with proper permissions' do
      it 'generates a pull request' do
        allow(::SupplyChain::RemediationService).to receive(:generate_pull_request).and_return({
          success: true,
          pr_url: 'https://github.com/test/repo/pull/1',
          pr_number: 1
        })

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']['status']).to eq('pr_generated')
        expect(data['pr_url']).to eq('https://github.com/test/repo/pull/1')
        expect(data['message']).to eq('Pull request generated successfully')

        plan.reload
        expect(plan.pr_url).to eq('https://github.com/test/repo/pull/1')
        expect(plan.pr_number).to eq(1)
      end

      it 'returns error when plan is not approved' do
        plan.update!(status: 'draft')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:approved?).and_return(false)

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('Plan must be approved before generating PR', 422)
      end

      it 'returns error when generation fails' do
        allow(::SupplyChain::RemediationService).to receive(:generate_pull_request).and_return({
          success: false,
          error: 'Failed to create PR'
        })

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/generate_pr",
             headers: headers,
             as: :json

        expect_error_response('Failed to create PR', 422)
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

  describe 'POST /api/v1/supply_chain/remediation_plans/:id/approve' do
    let(:plan) do
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'pending_approval')
    end

    context 'with admin permissions' do
      it 'approves the remediation plan' do
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pending_approval?).and_return(true)
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:approve!)
        allow(SupplyChainChannel).to receive(:broadcast_to_account)

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/approve",
             params: { comment: 'Approved for production' },
             headers: admin_headers,
             as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Remediation plan approved')
        expect(SupplyChainChannel).to have_received(:broadcast_to_account)
      end

      it 'returns error when plan is not pending approval' do
        plan.update!(status: 'draft')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pending_approval?).and_return(false)

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
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'pending_approval')
    end

    context 'with admin permissions' do
      it 'rejects the remediation plan' do
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pending_approval?).and_return(true)
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:reject!)

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             params: { reason: 'Not suitable for production' },
             headers: admin_headers,
             as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Remediation plan rejected')
      end

      it 'returns error when plan is not pending approval' do
        plan.update!(status: 'draft')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pending_approval?).and_return(false)

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/reject",
             params: { reason: 'Test' },
             headers: admin_headers,
             as: :json

        expect_error_response('Plan is not pending approval', 422)
      end

      it 'returns error when reason is missing' do
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pending_approval?).and_return(true)

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
      create(:supply_chain_remediation_plan,
             account: account,
             created_by: user,
             status: 'approved')
    end

    context 'with proper permissions' do
      it 'starts remediation execution' do
        allow(::SupplyChain::RemediationExecutionJob).to receive(:perform_later)

        post "/api/v1/supply_chain/remediation_plans/#{plan.id}/execute",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['remediation_plan']['status']).to eq('executing')
        expect(data['message']).to eq('Remediation execution started')

        plan.reload
        expect(plan.execution_started_at).to be_present
        expect(::SupplyChain::RemediationExecutionJob)
          .to have_received(:perform_later).with(plan.id, user.id)
      end

      it 'returns error when plan is not approved' do
        plan.update!(status: 'draft')
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:approved?).and_return(false)
        allow_any_instance_of(SupplyChain::RemediationPlan).to receive(:pr_generated?).and_return(false)

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
end

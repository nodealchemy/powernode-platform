# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::PipelineApprovals', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['git.approvals.read', 'git.approvals.manage']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['git.approvals.read']) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/git/pipeline_approvals' do
    let!(:approval1) { create(:devops_git_pipeline_approval, account: account, status: 'pending') }
    let!(:approval2) { create(:devops_git_pipeline_approval, account: account, status: 'approved') }
    let!(:other_approval) { create(:devops_git_pipeline_approval, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of pipeline approvals for current account' do
        get '/api/v1/git/pipeline_approvals', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['approvals']).to be_an(Array)
        expect(data['approvals'].length).to eq(2)
        expect(data['approvals'].none? { |a| a['id'] == other_approval.id }).to be true
        expect(data['stats']).to include('total', 'pending', 'approved', 'rejected', 'expired')
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        get '/api/v1/git/pipeline_approvals', params: { status: 'pending' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['approvals'].length).to eq(1)
        expect(data['approvals'].first['status']).to eq('pending')
      end

      it 'filters by environment' do
        approval3 = create(:devops_git_pipeline_approval, account: account, environment: 'production')

        get '/api/v1/git/pipeline_approvals', params: { environment: 'production' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['approvals'].all? { |a| a['environment'] == 'production' }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/git/pipeline_approvals', params: { page: 1, per_page: 1 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['approvals'].length).to eq(1)
        expect(data['pagination']['current_page']).to eq(1)
        expect(data['pagination']['per_page']).to eq(1)
      end

      it 'sorts by created_at' do
        get '/api/v1/git/pipeline_approvals', params: { sort: 'created_at', direction: 'asc' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['approvals']).to be_an(Array)
      end
    end

    context 'without git.approvals.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/pipeline_approvals', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/pipeline_approvals', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/git/pipeline_approvals/pending' do
    let!(:pending_approval) { create(:devops_git_pipeline_approval, account: account, status: 'pending') }
    let!(:approved_approval) { create(:devops_git_pipeline_approval, account: account, status: 'approved') }

    context 'with proper permissions' do
      it 'returns only active pending approvals' do
        get '/api/v1/git/pipeline_approvals/pending', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['approvals']).to be_an(Array)
        expect(data['count']).to be_a(Integer)
      end
    end

    context 'without git.approvals.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/pipeline_approvals/pending', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/pipeline_approvals/:id' do
    let(:approval) { create(:devops_git_pipeline_approval, account: account) }
    let(:other_approval) { create(:devops_git_pipeline_approval, account: other_account) }

    context 'with proper permissions' do
      it 'returns approval details' do
        get "/api/v1/git/pipeline_approvals/#{approval.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['approval']).to include(
          'id' => approval.id,
          'gate_name' => approval.gate_name,
          'status' => approval.status
        )
      end

      it 'returns not found for non-existent approval' do
        get "/api/v1/git/pipeline_approvals/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing approval from different account' do
      it 'returns not found error' do
        get "/api/v1/git/pipeline_approvals/#{other_approval.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.approvals.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/pipeline_approvals/#{approval.id}", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_approvals/:id/approve' do
    let(:approval) { create(:devops_git_pipeline_approval, account: account, status: 'pending') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_respond?).and_return(true)
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_user_approve?).and_return(true)
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:approve!)
        allow(DevopsPipelineChannel).to receive(:broadcast_approval_status)
        allow(NotificationService).to receive(:send_to_account)
      end

      it 'approves the pipeline approval' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/approve",
             params: { comment: 'Approved' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Approval granted successfully')
      end

      it 'returns error when approval cannot be responded to' do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_respond?).and_return(false)

        post "/api/v1/git/pipeline_approvals/#{approval.id}/approve", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Cannot approve this request')
      end

      it 'returns forbidden when user cannot approve' do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_user_approve?).and_return(false)

        post "/api/v1/git/pipeline_approvals/#{approval.id}/approve", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to eq('You are not authorized to approve this request')
      end
    end

    context 'without git.approvals.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/approve", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_approvals/:id/reject' do
    let(:approval) { create(:devops_git_pipeline_approval, account: account, status: 'pending') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_respond?).and_return(true)
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:reject!)
        allow(DevopsPipelineChannel).to receive(:broadcast_approval_status)
        allow(NotificationService).to receive(:send_to_account)
        allow_any_instance_of(Devops::GitPipeline).to receive(:update!)
      end

      it 'rejects the pipeline approval' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/reject",
             params: { comment: 'Rejected' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Approval rejected')
      end

      it 'returns error when approval cannot be responded to' do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:can_respond?).and_return(false)

        post "/api/v1/git/pipeline_approvals/#{approval.id}/reject", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Cannot reject this request')
      end
    end

    context 'without git.approvals.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/reject", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipeline_approvals/:id/cancel' do
    let(:approval) { create(:devops_git_pipeline_approval, account: account, status: 'pending') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:pending?).and_return(true)
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:cancel!)
      end

      it 'cancels the pipeline approval' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/cancel", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Approval cancelled')
      end

      it 'returns error when approval is not pending' do
        allow_any_instance_of(Devops::GitPipelineApproval).to receive(:pending?).and_return(false)

        post "/api/v1/git/pipeline_approvals/#{approval.id}/cancel", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Can only cancel pending approvals')
      end
    end

    context 'without git.approvals.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/pipeline_approvals/#{approval.id}/cancel", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

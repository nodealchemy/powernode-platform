# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::AiWorkflowApprovals', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_node) { create(:ai_workflow_node, :human_approval, ai_workflow: workflow) }
  let(:workflow_run) { create(:ai_workflow_run, ai_workflow: workflow, account: account, status: 'running') }
  let(:node_execution) do
    create(:ai_workflow_node_execution,
           ai_workflow_run: workflow_run,
           ai_workflow_node: workflow_node,
           status: 'waiting_approval',
           metadata: { 'approval_message' => 'Please approve this step' })
  end

  # Internal API requires worker service token authentication
  let(:headers) { { 'Authorization' => "Bearer #{service_token}" } }

  describe 'GET /api/v1/internal/ai_workflow_approvals/:node_execution_id' do
    it 'returns node execution details' do
      get "/api/v1/internal/ai_workflow_approvals/#{node_execution.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(node_execution.id)
      expect(json['data']['node_type']).to eq('human_approval')
      expect(json['data']['approval_message']).to eq('Please approve this step')
      expect(json['data']['workflow']['name']).to eq(workflow.name)
    end

    it 'returns not found for non-existent execution' do
      get '/api/v1/internal/ai_workflow_approvals/non-existent-id', headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/internal/ai_workflow_approvals/:node_execution_id/create_tokens' do
    let(:recipients) do
      [
        { 'type' => 'email', 'value' => 'approver1@example.com' },
        { 'type' => 'email', 'value' => 'approver2@example.com' }
      ]
    end

    it 'creates approval tokens for recipients' do
      post "/api/v1/internal/ai_workflow_approvals/#{node_execution.id}/create_tokens",
           params: { recipients: recipients },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['tokens'].length).to eq(2)
      expect(json['data']['tokens'][0]['recipient_email']).to eq('approver1@example.com')
      expect(json['data']['tokens'][0]['raw_token']).to be_present
    end

    it 'creates tokens for user recipients' do
      recipients_with_user = [
        { 'type' => 'user_id', 'value' => user.id }
      ]

      post "/api/v1/internal/ai_workflow_approvals/#{node_execution.id}/create_tokens",
           params: { recipients: recipients_with_user },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['tokens'][0]['recipient_email']).to eq(user.email)
    end

    it 'skips recipients with blank email' do
      recipients_with_blank = [
        { 'type' => 'email', 'value' => '' },
        { 'type' => 'email', 'value' => 'valid@example.com' }
      ]

      post "/api/v1/internal/ai_workflow_approvals/#{node_execution.id}/create_tokens",
           params: { recipients: recipients_with_blank },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['data']['tokens'].length).to eq(1)
    end
  end

  describe 'POST /api/v1/internal/ai_workflow_approvals/expire_stale' do
    context 'with no expired tokens' do
      it 'returns zero counts' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(0)
        expect(json['data']['failed_executions_count']).to eq(0)
      end
    end

    context 'with expired pending tokens' do
      let!(:expired_token1) do
        create(:ai_workflow_approval_token,
               ai_workflow_node_execution: node_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let(:other_node) { create(:ai_workflow_node, :human_approval, ai_workflow: workflow, name: 'Other Approval') }
      let(:other_execution) do
        create(:ai_workflow_node_execution,
               ai_workflow_run: workflow_run,
               ai_workflow_node: other_node,
               status: 'waiting_approval',
               metadata: { 'approval_message' => 'Approve this too' })
      end
      let!(:expired_token2) do
        create(:ai_workflow_approval_token,
               ai_workflow_node_execution: other_execution,
               status: 'pending',
               expires_at: 2.hours.ago)
      end

      before do
        # Mock approve_execution! to avoid triggering full workflow logic
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:approve_execution!).and_return(true)
      end

      it 'expires the stale tokens' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(2)

        # Verify tokens are marked as expired
        expect(expired_token1.reload.status).to eq('expired')
        expect(expired_token2.reload.status).to eq('expired')
      end

      it 'fails node executions with all tokens expired' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_executions_count']).to eq(2)
      end

      it 'returns affected execution IDs' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['affected_execution_ids']).to contain_exactly(
          node_execution.id,
          other_execution.id
        )
      end
    end

    context 'with mixed token states' do
      let!(:expired_token) do
        create(:ai_workflow_approval_token,
               ai_workflow_node_execution: node_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let!(:valid_token) do
        create(:ai_workflow_approval_token,
               ai_workflow_node_execution: node_execution,
               status: 'pending',
               expires_at: 1.day.from_now,
               recipient_email: 'other@example.com')
      end

      before do
        allow_any_instance_of(AiWorkflowNodeExecution).to receive(:approve_execution!).and_return(true)
      end

      it 'only expires stale tokens' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(1)

        expect(expired_token.reload.status).to eq('expired')
        expect(valid_token.reload.status).to eq('pending')
      end

      it 'does not fail execution if valid tokens remain' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_executions_count']).to eq(0)
      end
    end

    context 'with already used tokens' do
      let!(:approved_token) do
        create(:ai_workflow_approval_token,
               ai_workflow_node_execution: node_execution,
               status: 'approved',
               expires_at: 1.hour.ago,
               responded_at: 2.hours.ago)
      end

      it 'does not expire already used tokens' do
        post '/api/v1/internal/ai_workflow_approvals/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(0)

        expect(approved_token.reload.status).to eq('approved')
      end
    end
  end
end

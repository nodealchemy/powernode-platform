# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AiWorkflows::ApprovalTokens', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_node) { create(:ai_workflow_node, workflow: workflow, node_type: 'human_approval') }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account, status: 'running') }
  let(:node_execution) do
    create(:ai_workflow_node_execution,
           workflow_run: workflow_run,
           node: workflow_node,
           status: 'waiting_approval',
           metadata: { 'approval_message' => 'Please approve this step' })
  end

  let!(:approval_token) do
    token, @raw_token = Ai::WorkflowApprovalToken.create_for_recipient(
      node_execution: node_execution,
      recipient_email: 'approver@example.com',
      expires_in: 24.hours
    )
    token
  end

  let(:raw_token) { @raw_token }

  describe 'GET /api/v1/ai_workflows/approval_tokens/:token' do
    context 'with valid token' do
      it 'returns token details without authentication' do
        get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['status']).to eq('pending')
        expect(json['data']['recipient_email']).to eq('approver@example.com')
        expect(json['data']['can_respond']).to be true
        expect(json['data']['workflow']['name']).to eq(workflow.name)
        expect(json['data']['node_execution']['node_type']).to eq('human_approval')
      end

      it 'includes time remaining' do
        get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']['time_remaining_seconds']).to be > 0
        expect(json['data']['expires_at']).to be_present
      end

      it 'includes require_comment setting' do
        get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']).to have_key('require_comment')
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        get '/api/v1/ai_workflows/approval_tokens/invalid_token_12345'

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Invalid')
      end
    end

    context 'with expired token' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'still returns token details but shows cannot respond' do
        get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['can_respond']).to be false
        expect(json['data']['time_remaining_seconds']).to eq(0)
      end
    end

    context 'with already used token' do
      before do
        approval_token.update!(status: 'approved', responded_at: Time.current)
      end

      it 'returns token details showing already responded' do
        get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['status']).to eq('approved')
        expect(json['data']['can_respond']).to be false
      end
    end
  end

  describe 'POST /api/v1/ai_workflows/approval_tokens/:token/approve' do
    before do
      allow_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!).and_return(true)
    end

    context 'with valid pending token' do
      it 'approves the token without authentication' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             params: { comment: 'Looks good!' },
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('approved')
        expect(json['data']['token']['status']).to eq('approved')
      end

      it 'records the comment' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             params: { comment: 'LGTM!' },
             as: :json

        expect(response).to have_http_status(:ok)
        approval_token.reload
        expect(approval_token.response_comment).to eq('LGTM!')
        expect(approval_token.responded_at).to be_present
      end

      it 'works without a comment when not required' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'calls approve_execution! on node execution' do
        expect_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!)
          .with(nil, hash_including('approved' => true))
          .and_return(true)

        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             params: { comment: 'Approved' },
             as: :json
      end
    end

    context 'with comment required' do
      before do
        workflow_node.update!(configuration: workflow_node.configuration.merge('require_comment' => true))
      end

      it 'rejects approval without comment' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('comment')
      end

      it 'accepts approval with comment' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             params: { comment: 'Required comment provided' },
             as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        post '/api/v1/ai_workflows/approval_tokens/invalid_token/approve',
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with expired token' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'returns unprocessable entity with expiry message' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('expired')
      end
    end

    context 'with already used token' do
      before do
        approval_token.update!(status: 'approved', responded_at: Time.current)
      end

      it 'returns unprocessable entity' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('already been used')
      end
    end
  end

  describe 'POST /api/v1/ai_workflows/approval_tokens/:token/reject' do
    before do
      allow_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!).and_return(true)
    end

    context 'with valid pending token' do
      it 'rejects the token without authentication' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             params: { comment: 'Needs more work' },
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('rejected')
        expect(json['data']['token']['status']).to eq('rejected')
      end

      it 'records the comment' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             params: { comment: 'Not ready for production' },
             as: :json

        approval_token.reload
        expect(approval_token.response_comment).to eq('Not ready for production')
        expect(approval_token.status).to eq('rejected')
      end

      it 'calls approve_execution! with approved=false' do
        expect_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!)
          .with(nil, hash_including('approved' => false))
          .and_return(true)

        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             params: { comment: 'Rejected' },
             as: :json
      end
    end

    context 'with comment required' do
      before do
        workflow_node.update!(configuration: workflow_node.configuration.merge('require_comment' => true))
      end

      it 'rejects without comment' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('comment')
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        post '/api/v1/ai_workflows/approval_tokens/invalid_token/reject',
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with expired token' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'returns unprocessable entity' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('expired')
      end
    end

    context 'with already used token' do
      before do
        approval_token.update!(status: 'rejected', responded_at: Time.current)
      end

      it 'returns unprocessable entity' do
        post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject",
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'authentication behavior' do
    it 'does not require JWT authentication for show' do
      get "/api/v1/ai_workflows/approval_tokens/#{raw_token}"
      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'does not require JWT authentication for approve' do
      allow_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!).and_return(true)

      post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/approve", as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'does not require JWT authentication for reject' do
      allow_any_instance_of(Ai::WorkflowNodeExecution).to receive(:approve_execution!).and_return(true)

      post "/api/v1/ai_workflows/approval_tokens/#{raw_token}/reject", as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::CiCd::StepApprovals', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:pipeline) { create(:ci_cd_pipeline, account: account) }
  let(:pipeline_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline) }
  let(:pipeline_run) { create(:ci_cd_pipeline_run, :running, pipeline: pipeline) }
  let(:step_execution) do
    create(:ci_cd_step_execution,
           :waiting_approval,
           pipeline_run: pipeline_run,
           pipeline_step: pipeline_step)
  end

  let!(:approval_token) do
    token, @raw_token = CiCd::StepApprovalToken.create_for_recipient(
      step_execution: step_execution,
      recipient_email: 'approver@example.com',
      expires_in: 24.hours
    )
    token
  end

  let(:raw_token) { @raw_token }

  describe 'GET /api/v1/ci_cd/step_approvals/:token' do
    context 'with valid token' do
      it 'returns token details without authentication' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['status']).to eq('pending')
        expect(json['data']['step_name']).to eq(pipeline_step.name)
        expect(json['data']['pipeline_name']).to eq(pipeline.name)
        expect(json['data']['run_number']).to eq(pipeline_run.run_number)
      end

      it 'includes time remaining and expiry' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']['time_remaining_seconds']).to be > 0
        expect(json['data']['expires_at']).to be_present
      end

      it 'includes trigger information' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']['trigger_type']).to eq(pipeline_run.trigger_type)
        expect(json['data']['trigger_context']).to be_present
      end

      it 'includes step configuration' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']['step_configuration']).to be_present
        expect(json['data']['step_configuration']['step_type']).to eq(pipeline_step.step_type)
      end

      it 'includes requires_comment setting' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        json = JSON.parse(response.body)
        expect(json['data']).to have_key('requires_comment')
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        get '/api/v1/ci_cd/step_approvals/invalid_token_12345'

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Invalid')
      end
    end

    context 'with already used token' do
      before do
        approval_token.update!(status: 'approved', responded_at: Time.current)
      end

      it 'returns gone status' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        expect(response).to have_http_status(:gone)
        json = JSON.parse(response.body)
        expect(json['error']).to include('approved')
      end
    end

    context 'with expired token that is still pending' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'returns gone status' do
        get "/api/v1/ci_cd/step_approvals/#{raw_token}"

        # Token is pending but expired, so can_respond? is false
        expect(response).to have_http_status(:gone)
      end
    end
  end

  describe 'POST /api/v1/ci_cd/step_approvals/:token/approve' do
    before do
      allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)
    end

    context 'with valid pending token' do
      it 'approves the step without authentication' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             params: { comment: 'Approved for deployment' },
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['status']).to eq('approved')
        expect(json['data']['message']).to include('approved')
      end

      it 'records the approval comment' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             params: { comment: 'LGTM - ready for production' },
             as: :json

        approval_token.reload
        expect(approval_token.status).to eq('approved')
        expect(approval_token.response_comment).to eq('LGTM - ready for production')
        expect(approval_token.responded_at).to be_present
      end

      it 'works without a comment when not required' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'calls handle_approval_response! on step execution' do
        expect_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!)
          .with(approved: true, comment: 'Ship it!', by_user: nil)
          .and_return(true)

        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             params: { comment: 'Ship it!' },
             as: :json
      end
    end

    context 'with comment required' do
      let(:pipeline_step_with_comment) do
        create(:ci_cd_pipeline_step, :requires_comment, pipeline: pipeline, name: 'Comment Required Step')
      end
      let(:step_execution_with_comment) do
        create(:ci_cd_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: pipeline_step_with_comment)
      end
      let!(:token_with_comment_req) do
        token, @raw_token_comment = CiCd::StepApprovalToken.create_for_recipient(
          step_execution: step_execution_with_comment,
          recipient_email: 'approver@example.com'
        )
        token
      end

      it 'rejects approval without comment' do
        post "/api/v1/ci_cd/step_approvals/#{@raw_token_comment}/approve",
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('comment')
      end

      it 'accepts approval with comment' do
        post "/api/v1/ci_cd/step_approvals/#{@raw_token_comment}/approve",
             params: { comment: 'Required comment here' },
             as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        post '/api/v1/ci_cd/step_approvals/invalid_token/approve',
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with expired token' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'returns gone status' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:gone)
      end
    end

    context 'with already approved token' do
      before do
        approval_token.update!(status: 'approved', responded_at: Time.current)
      end

      it 'returns gone status' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:gone)
        json = JSON.parse(response.body)
        expect(json['error']).to include('approved')
      end
    end

    context 'with already rejected token' do
      before do
        approval_token.update!(status: 'rejected', responded_at: Time.current)
      end

      it 'returns gone status' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
             as: :json

        expect(response).to have_http_status(:gone)
        json = JSON.parse(response.body)
        expect(json['error']).to include('rejected')
      end
    end
  end

  describe 'POST /api/v1/ci_cd/step_approvals/:token/reject' do
    before do
      allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)
    end

    context 'with valid pending token' do
      it 'rejects the step without authentication' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
             params: { comment: 'Security concerns' },
             as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['status']).to eq('rejected')
        expect(json['data']['message']).to include('rejected')
      end

      it 'records the rejection comment' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
             params: { comment: 'Not ready - tests failing' },
             as: :json

        approval_token.reload
        expect(approval_token.status).to eq('rejected')
        expect(approval_token.response_comment).to eq('Not ready - tests failing')
      end

      it 'calls handle_approval_response! with approved=false' do
        expect_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!)
          .with(approved: false, comment: 'Blocked', by_user: nil)
          .and_return(true)

        post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
             params: { comment: 'Blocked' },
             as: :json
      end
    end

    context 'with comment required' do
      let(:pipeline_step_with_comment) do
        create(:ci_cd_pipeline_step, :requires_comment, pipeline: pipeline, name: 'Reject Comment Step')
      end
      let(:step_execution_with_comment) do
        create(:ci_cd_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: pipeline_step_with_comment)
      end
      let!(:token_with_comment_req) do
        token, @raw_token_reject = CiCd::StepApprovalToken.create_for_recipient(
          step_execution: step_execution_with_comment,
          recipient_email: 'approver@example.com'
        )
        token
      end

      it 'rejects without comment' do
        post "/api/v1/ci_cd/step_approvals/#{@raw_token_reject}/reject",
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('comment')
      end

      it 'accepts rejection with comment' do
        post "/api/v1/ci_cd/step_approvals/#{@raw_token_reject}/reject",
             params: { comment: 'Required rejection reason' },
             as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with invalid token' do
      it 'returns not found' do
        post '/api/v1/ci_cd/step_approvals/invalid_token/reject',
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with expired token' do
      before do
        approval_token.update!(expires_at: 1.hour.ago)
      end

      it 'returns gone status' do
        post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
             as: :json

        expect(response).to have_http_status(:gone)
      end
    end
  end

  describe 'authentication behavior' do
    it 'does not require JWT authentication for show' do
      get "/api/v1/ci_cd/step_approvals/#{raw_token}"
      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'does not require JWT authentication for approve' do
      allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)

      post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve", as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end

    it 'does not require JWT authentication for reject' do
      allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)

      post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject", as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  describe 'concurrent approval attempts' do
    before do
      allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)
    end

    it 'only allows one successful approval' do
      # First approval succeeds
      post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
           params: { comment: 'First approval' },
           as: :json
      expect(response).to have_http_status(:ok)

      # Second approval fails
      post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
           params: { comment: 'Second approval' },
           as: :json
      expect(response).to have_http_status(:gone)
    end

    it 'prevents rejection after approval' do
      post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
           params: { comment: 'Approved' },
           as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
           params: { comment: 'Try to reject' },
           as: :json
      expect(response).to have_http_status(:gone)
    end

    it 'prevents approval after rejection' do
      post "/api/v1/ci_cd/step_approvals/#{raw_token}/reject",
           params: { comment: 'Rejected' },
           as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/ci_cd/step_approvals/#{raw_token}/approve",
           params: { comment: 'Try to approve' },
           as: :json
      expect(response).to have_http_status(:gone)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::CiCd::ApprovalTokens', type: :request do
  let(:account) { create(:account) }
  let(:pipeline) { create(:ci_cd_pipeline, account: account) }
  let(:pipeline_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline) }
  let(:pipeline_run) { create(:ci_cd_pipeline_run, :running, pipeline: pipeline) }
  let(:step_execution) do
    create(:ci_cd_step_execution,
           :waiting_approval,
           pipeline_run: pipeline_run,
           pipeline_step: pipeline_step)
  end

  # Internal API requires worker service token authentication
  let(:headers) { { 'Authorization' => "Bearer #{service_token}" } }

  describe 'POST /api/v1/internal/ci_cd/approval_tokens/expire_stale' do
    context 'with no expired tokens' do
      it 'returns zero counts' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(0)
        expect(json['data']['failed_steps_count']).to eq(0)
      end
    end

    context 'with expired pending tokens' do
      let!(:expired_token1) do
        create(:ci_cd_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let(:other_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline, name: 'Other Step') }
      let(:other_execution) do
        create(:ci_cd_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: other_step)
      end
      let!(:expired_token2) do
        create(:ci_cd_step_approval_token,
               step_execution: other_execution,
               status: 'pending',
               expires_at: 2.hours.ago)
      end

      before do
        # Mock handle_approval_response! to avoid triggering full workflow logic
        allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)
      end

      it 'expires the stale tokens' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(2)

        # Verify tokens are marked as expired
        expect(expired_token1.reload.status).to eq('expired')
        expect(expired_token2.reload.status).to eq('expired')
      end

      it 'fails step executions with all tokens expired' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_steps_count']).to eq(2)
      end

      it 'returns affected execution IDs' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['affected_execution_ids']).to contain_exactly(
          step_execution.id,
          other_execution.id
        )
      end
    end

    context 'with mixed token states' do
      let!(:expired_token) do
        create(:ci_cd_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let!(:valid_token) do
        create(:ci_cd_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.day.from_now,
               recipient_email: 'other@example.com')
      end

      before do
        allow_any_instance_of(CiCd::StepExecution).to receive(:handle_approval_response!).and_return(true)
      end

      it 'only expires stale tokens' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(1)

        expect(expired_token.reload.status).to eq('expired')
        expect(valid_token.reload.status).to eq('pending')
      end

      it 'does not fail execution if valid tokens remain' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_steps_count']).to eq(0)
      end
    end

    context 'with already used tokens' do
      let!(:approved_token) do
        create(:ci_cd_step_approval_token,
               step_execution: step_execution,
               status: 'approved',
               expires_at: 1.hour.ago,
               responded_at: 2.hours.ago)
      end

      it 'does not expire already used tokens' do
        post '/api/v1/internal/ci_cd/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(0)

        expect(approved_token.reload.status).to eq('approved')
      end
    end
  end

  describe 'GET /api/v1/internal/ci_cd/approval_tokens/pending_count' do
    context 'with no pending tokens' do
      it 'returns zero counts' do
        get '/api/v1/internal/ci_cd/approval_tokens/pending_count', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['total_pending']).to eq(0)
        expect(json['data']['expiring_within_hour']).to eq(0)
      end
    end

    context 'with pending tokens' do
      let!(:normal_token) do
        create(:ci_cd_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 2.days.from_now)
      end

      let(:other_step) { create(:ci_cd_pipeline_step, :with_approval, pipeline: pipeline, name: 'Other Step') }
      let(:other_execution) do
        create(:ci_cd_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: other_step)
      end
      let!(:expiring_soon_token) do
        create(:ci_cd_step_approval_token,
               step_execution: other_execution,
               status: 'pending',
               expires_at: 30.minutes.from_now)
      end

      it 'returns correct counts' do
        get '/api/v1/internal/ci_cd/approval_tokens/pending_count', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['total_pending']).to eq(2)
        expect(json['data']['expiring_within_hour']).to eq(1)
      end
    end
  end
end

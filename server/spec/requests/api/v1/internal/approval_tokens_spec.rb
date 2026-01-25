# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::ApprovalTokens', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Service token authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:pipeline) do
    Devops::Pipeline.create!(
      account: account,
      name: 'Test Pipeline',
      slug: 'test-pipeline',
      description: 'Test pipeline for approval tokens'
    )
  end

  let(:pipeline_step) do
    Devops::PipelineStep.create!(
      pipeline: pipeline,
      name: 'Approval Step',
      step_type: 'manual_approval',
      position: 1,
      requires_approval: true,
      approval_timeout_hours: 24,
      approval_requires_comment: true
    )
  end

  let(:pipeline_run) do
    Devops::PipelineRun.create!(
      pipeline: pipeline,
      run_number: 1,
      trigger_type: 'manual',
      status: 'pending'
    )
  end

  let(:step_execution) do
    Devops::StepExecution.create!(
      pipeline_run: pipeline_run,
      pipeline_step: pipeline_step,
      step_name: 'Approval Step',
      step_type: 'manual_approval',
      status: 'waiting_approval',
      position: 1
    )
  end

  describe 'GET /api/v1/internal/approval_tokens/:step_execution_id' do
    context 'with service token authentication' do
      it 'returns step execution details' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => step_execution.id,
          'step_name' => 'Approval Step',
          'step_type' => 'manual_approval',
          'status' => 'waiting_approval'
        )
      end

      it 'includes pipeline step information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_step_data = response_data['data']['pipeline_step']

        expect(pipeline_step_data).to include(
          'id' => pipeline_step.id,
          'name' => 'Approval Step',
          'requires_approval' => true,
          'approval_timeout_hours' => 24,
          'approval_requires_comment' => true
        )
      end

      it 'includes pipeline run information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_run_data = response_data['data']['pipeline_run']

        expect(pipeline_run_data).to include(
          'id' => pipeline_run.id,
          'run_number' => 1,
          'trigger_type' => 'manual',
          'status' => 'pending'
        )
      end

      it 'includes pipeline information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_data = response_data['data']['pipeline']

        expect(pipeline_data).to include(
          'id' => pipeline.id,
          'name' => 'Test Pipeline',
          'slug' => 'test-pipeline',
          'account_id' => account.id
        )
      end
    end

    context 'when step execution does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/approval_tokens/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Step execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/approval_tokens/:step_execution_id/create_tokens' do
    context 'with service token authentication' do
      it 'creates approval tokens for recipients with email only' do
        recipients = [
          { 'value' => 'user1@example.com' },
          { 'value' => 'user2@example.com' }
        ]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tokens'].size).to eq(2)
        tokens = response_data['data']['tokens']

        expect(tokens.first).to include(
          'id',
          'raw_token',
          'recipient_email',
          'expires_at'
        )

        expect(tokens.first['recipient_email']).to eq('user1@example.com')
        expect(tokens.second['recipient_email']).to eq('user2@example.com')
      end

      it 'creates approval tokens for recipients with user_id' do
        recipients = [
          { 'email' => user.email, 'user_id' => user.id }
        ]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        tokens = response_data['data']['tokens']
        expect(tokens.size).to eq(1)
        expect(tokens.first['recipient_email']).to eq(user.email)
      end

      it 'creates tokens with expiration based on approval timeout' do
        recipients = [{ 'value' => 'user@example.com' }]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        token_data = response_data['data']['tokens'].first
        expect(token_data['expires_at']).to be_present

        expires_at = Time.parse(token_data['expires_at'])
        expected_expiry = Time.current + 24.hours

        expect(expires_at).to be_within(1.minute).of(expected_expiry)
      end

      it 'returns raw tokens for email delivery' do
        recipients = [{ 'value' => 'user@example.com' }]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        token_data = response_data['data']['tokens'].first
        expect(token_data['raw_token']).to be_present
        expect(token_data['raw_token']).to be_a(String)
      end

      it 'handles empty recipients array' do
        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: [] },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['tokens']).to eq([])
      end
    end

    context 'when step execution does not exist' do
      it 'returns not found error' do
        recipients = [{ 'value' => 'user@example.com' }]

        post '/api/v1/internal/approval_tokens/nonexistent-id/create_tokens',
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_error_response('Step execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        recipients = [{ 'value' => 'user@example.com' }]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

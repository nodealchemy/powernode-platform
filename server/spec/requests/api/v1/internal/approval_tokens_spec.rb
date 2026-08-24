# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::ApprovalTokens', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  let(:pipeline) { create(:devops_pipeline, account: account) }

  let(:pipeline_step) do
    create(:devops_pipeline_step, :with_approval, pipeline: pipeline)
  end

  let(:pipeline_run) do
    create(:devops_pipeline_run, pipeline: pipeline, status: 'pending')
  end

  let(:step_execution) do
    create(:devops_step_execution,
           :waiting_approval,
           pipeline_run: pipeline_run,
           pipeline_step: pipeline_step)
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
          'status' => 'waiting_approval'
        )
        expect(response_data['data']).to have_key('step_name')
        expect(response_data['data']).to have_key('step_type')
      end

      it 'includes pipeline step information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_step_data = response_data['data']['pipeline_step']

        expect(pipeline_step_data).to include(
          'id' => pipeline_step.id,
          'requires_approval' => true
        )
        expect(pipeline_step_data).to have_key('name')
      end

      it 'includes pipeline run information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_run_data = response_data['data']['pipeline_run']

        expect(pipeline_run_data).to include(
          'id' => pipeline_run.id,
          'status' => 'pending'
        )
        expect(pipeline_run_data).to have_key('trigger_type')
      end

      it 'includes pipeline information' do
        get "/api/v1/internal/approval_tokens/#{step_execution.id}",
            headers: internal_headers,
            as: :json

        response_data = json_response
        pipeline_data = response_data['data']['pipeline']

        expect(pipeline_data).to include(
          'id' => pipeline.id,
          'account_id' => account.id
        )
        expect(pipeline_data).to have_key('name')
        expect(pipeline_data).to have_key('slug')
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
      # SECURITY (offer 01a02aac-195e, DEFECT 2): the recipient set derives from
      # the step's OWN configured approver policy, NEVER from the request body.
      # `:with_approval` configures a single approver, approver@example.com.
      it 'mints for the step-configured approver and IGNORES caller-supplied recipients' do
        recipients = [
          { 'value' => 'attacker1@evil.example' },
          { 'value' => 'attacker2@evil.example' }
        ]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        tokens = json_response['data']['tokens']

        # One token, for the configured approver — not the two attacker addresses.
        expect(tokens.size).to eq(1)
        expect(tokens.first).to include('id', 'raw_token', 'recipient_email', 'expires_at')
        expect(tokens.first['recipient_email']).to eq('approver@example.com')
        emails = tokens.map { |t| t['recipient_email'] }
        expect(emails).not_to include('attacker1@evil.example', 'attacker2@evil.example')
      end

      it 'resolves a user_id-typed approver from the pipeline policy' do
        pipeline.update!(notification_recipients: [ { 'type' => 'user_id', 'value' => user.id } ])
        # Step with no step-level override falls back to the pipeline policy.
        step = create(:devops_pipeline_step, pipeline: pipeline,
                      requires_approval: true, approval_settings: { 'timeout_hours' => 24 })
        execution = create(:devops_step_execution, :waiting_approval,
                           pipeline_run: pipeline_run, pipeline_step: step)

        post "/api/v1/internal/approval_tokens/#{execution.id}/create_tokens",
             params: { recipients: [ { 'value' => 'attacker@evil.example' } ] },
             headers: internal_headers,
             as: :json

        expect_success_response
        tokens = json_response['data']['tokens']
        expect(tokens.size).to eq(1)
        expect(tokens.first['recipient_email']).to eq(user.email)
        expect(execution.approval_tokens.first.recipient_user_id).to eq(user.id)
      end

      it 'creates tokens with expiration' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        token_data = response_data['data']['tokens'].first
        expect(token_data['expires_at']).to be_present
      end

      it 'returns raw tokens for email delivery' do
        recipients = [ { 'value' => 'user@example.com' } ]

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

      it 'mints nothing when the step has no configured approvers' do
        # No step-level recipients and an empty pipeline policy -> no approvers,
        # regardless of what the caller puts in the body.
        step = create(:devops_pipeline_step, pipeline: pipeline,
                      requires_approval: true, approval_settings: { 'timeout_hours' => 24 })
        execution = create(:devops_step_execution, :waiting_approval,
                           pipeline_run: pipeline_run, pipeline_step: step)

        post "/api/v1/internal/approval_tokens/#{execution.id}/create_tokens",
             params: { recipients: [ { 'value' => 'attacker@evil.example' } ] },
             headers: internal_headers,
             as: :json

        expect_success_response
        expect(json_response['data']['tokens']).to eq([])
      end
    end

    context 'when step execution does not exist' do
      it 'returns not found error' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post '/api/v1/internal/approval_tokens/nonexistent-id/create_tokens',
             params: { recipients: recipients },
             headers: internal_headers,
             as: :json

        expect_error_response('Step execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post "/api/v1/internal/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

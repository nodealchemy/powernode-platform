# frozen_string_literal: true

require 'rails_helper'

# fc-27: merged from the former spec/requests/api/v1/internal/approval_tokens_spec.rb
# (show/create_tokens) into this file (expire_stale/pending_count) when their
# controllers merged into one Api::V1::Internal::Devops::ApprovalTokensController.
RSpec.describe 'Api::V1::Internal::Devops::ApprovalTokens', type: :request do
  let(:account) { create(:account) }

  # Internal API authenticates via mTLS: InternalBaseController includes
  # MtlsClientAuthentication and resolves the worker from the client-cert
  # subject CN forwarded by the reverse proxy. Specs simulate that by
  # setting the X-Forwarded-Tls-Client-Cert-Info header directly.
  let(:internal_worker) { create(:worker, account: account) }
  let(:headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  describe 'GET /api/v1/internal/devops/approval_tokens/:step_execution_id' do
    let(:user) { create(:user, account: account) }
    let(:pipeline) { create(:devops_pipeline, account: account) }
    let(:pipeline_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline) }
    let(:pipeline_run) { create(:devops_pipeline_run, pipeline: pipeline, status: 'pending') }
    let(:step_execution) do
      create(:devops_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: pipeline_step)
    end

    context 'with service token authentication' do
      it 'returns step execution details' do
        get "/api/v1/internal/devops/approval_tokens/#{step_execution.id}",
            headers: headers,
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
        get "/api/v1/internal/devops/approval_tokens/#{step_execution.id}",
            headers: headers,
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
        get "/api/v1/internal/devops/approval_tokens/#{step_execution.id}",
            headers: headers,
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
        get "/api/v1/internal/devops/approval_tokens/#{step_execution.id}",
            headers: headers,
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
        get '/api/v1/internal/devops/approval_tokens/nonexistent-id',
            headers: headers,
            as: :json

        expect_error_response('Step execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/devops/approval_tokens/#{step_execution.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/devops/approval_tokens/:step_execution_id/create_tokens' do
    let(:user) { create(:user, account: account) }
    let(:pipeline) { create(:devops_pipeline, account: account) }
    let(:pipeline_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline) }
    let(:pipeline_run) { create(:devops_pipeline_run, pipeline: pipeline, status: 'pending') }
    let(:step_execution) do
      create(:devops_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: pipeline_step)
    end

    context 'with service token authentication' do
      # SECURITY (offer 01a02aac-195e, DEFECT 2): the recipient set derives from
      # the step's OWN configured approver policy, NEVER from the request body.
      # `:with_approval` configures a single approver, approver@example.com.
      it 'mints for the step-configured approver and IGNORES caller-supplied recipients' do
        recipients = [
          { 'value' => 'attacker1@evil.example' },
          { 'value' => 'attacker2@evil.example' }
        ]

        post "/api/v1/internal/devops/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: headers,
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

        post "/api/v1/internal/devops/approval_tokens/#{execution.id}/create_tokens",
             params: { recipients: [ { 'value' => 'attacker@evil.example' } ] },
             headers: headers,
             as: :json

        expect_success_response
        tokens = json_response['data']['tokens']
        expect(tokens.size).to eq(1)
        expect(tokens.first['recipient_email']).to eq(user.email)
        expect(execution.approval_tokens.first.recipient_user_id).to eq(user.id)
      end

      it 'creates tokens with expiration' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post "/api/v1/internal/devops/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        token_data = response_data['data']['tokens'].first
        expect(token_data['expires_at']).to be_present
      end

      it 'returns raw tokens for email delivery' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post "/api/v1/internal/devops/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             headers: headers,
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

        post "/api/v1/internal/devops/approval_tokens/#{execution.id}/create_tokens",
             params: { recipients: [ { 'value' => 'attacker@evil.example' } ] },
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response['data']['tokens']).to eq([])
      end
    end

    context 'when step execution does not exist' do
      it 'returns not found error' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post '/api/v1/internal/devops/approval_tokens/nonexistent-id/create_tokens',
             params: { recipients: recipients },
             headers: headers,
             as: :json

        expect_error_response('Step execution not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        recipients = [ { 'value' => 'user@example.com' } ]

        post "/api/v1/internal/devops/approval_tokens/#{step_execution.id}/create_tokens",
             params: { recipients: recipients },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/devops/approval_tokens/expire_stale' do
    let(:pipeline) { create(:devops_pipeline, account: account) }
    let(:pipeline_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline) }
    let(:pipeline_run) { create(:devops_pipeline_run, :running, pipeline: pipeline) }
    let(:step_execution) do
      create(:devops_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: pipeline_step)
    end

    context 'with no expired tokens' do
      it 'returns zero counts' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(0)
        expect(json['data']['failed_steps_count']).to eq(0)
      end
    end

    context 'with expired pending tokens' do
      let!(:expired_token1) do
        create(:devops_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let(:other_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline, name: 'Other Step') }
      let(:other_execution) do
        create(:devops_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: other_step)
      end
      let!(:expired_token2) do
        create(:devops_step_approval_token,
               step_execution: other_execution,
               status: 'pending',
               expires_at: 2.hours.ago)
      end

      before do
        # Mock handle_approval_response! to avoid triggering full workflow logic
        allow_any_instance_of(Devops::StepExecution).to receive(:handle_approval_response!).and_return(true)
      end

      it 'expires the stale tokens' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['expired_count']).to eq(2)

        # Verify tokens are marked as expired
        expect(expired_token1.reload.status).to eq('expired')
        expect(expired_token2.reload.status).to eq('expired')
      end

      it 'fails step executions with all tokens expired' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_steps_count']).to eq(2)
      end

      it 'returns affected execution IDs' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['affected_execution_ids']).to contain_exactly(
          step_execution.id,
          other_execution.id
        )
      end
    end

    context 'with mixed token states' do
      let!(:expired_token) do
        create(:devops_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.hour.ago)
      end

      let!(:valid_token) do
        create(:devops_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 1.day.from_now,
               recipient_email: 'other@example.com')
      end

      before do
        allow_any_instance_of(Devops::StepExecution).to receive(:handle_approval_response!).and_return(true)
      end

      it 'only expires stale tokens' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(1)

        expect(expired_token.reload.status).to eq('expired')
        expect(valid_token.reload.status).to eq('pending')
      end

      it 'does not fail execution if valid tokens remain' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        json = JSON.parse(response.body)
        expect(json['data']['failed_steps_count']).to eq(0)
      end
    end

    context 'with already used tokens' do
      let!(:approved_token) do
        create(:devops_step_approval_token,
               step_execution: step_execution,
               status: 'approved',
               expires_at: 1.hour.ago,
               responded_at: 2.hours.ago)
      end

      it 'does not expire already used tokens' do
        post '/api/v1/internal/devops/approval_tokens/expire_stale', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['expired_count']).to eq(0)

        expect(approved_token.reload.status).to eq('approved')
      end
    end
  end

  describe 'GET /api/v1/internal/devops/approval_tokens/pending_count' do
    let(:pipeline) { create(:devops_pipeline, account: account) }
    let(:pipeline_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline) }
    let(:pipeline_run) { create(:devops_pipeline_run, :running, pipeline: pipeline) }
    let(:step_execution) do
      create(:devops_step_execution,
             :waiting_approval,
             pipeline_run: pipeline_run,
             pipeline_step: pipeline_step)
    end

    context 'with no pending tokens' do
      it 'returns zero counts' do
        get '/api/v1/internal/devops/approval_tokens/pending_count', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['total_pending']).to eq(0)
        expect(json['data']['expiring_within_hour']).to eq(0)
      end
    end

    context 'with pending tokens' do
      let!(:normal_token) do
        create(:devops_step_approval_token,
               step_execution: step_execution,
               status: 'pending',
               expires_at: 2.days.from_now)
      end

      let(:other_step) { create(:devops_pipeline_step, :with_approval, pipeline: pipeline, name: 'Other Step') }
      let(:other_execution) do
        create(:devops_step_execution,
               :waiting_approval,
               pipeline_run: pipeline_run,
               pipeline_step: other_step)
      end
      let!(:expiring_soon_token) do
        create(:devops_step_approval_token,
               step_execution: other_execution,
               status: 'pending',
               expires_at: 30.minutes.from_now)
      end

      it 'returns correct counts' do
        get '/api/v1/internal/devops/approval_tokens/pending_count', headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['total_pending']).to eq(2)
        expect(json['data']['expiring_within_hour']).to eq(1)
      end
    end
  end
end

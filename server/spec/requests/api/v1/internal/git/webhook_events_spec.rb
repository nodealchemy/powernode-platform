# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::WebhookEvents', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, git_provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:webhook_event) do
    create(:git_webhook_event,
           account: account,
           git_provider: git_provider,
           repository: repository,
           status: 'pending')
  end

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/git/webhook_events/:id' do
    context 'with valid internal authentication' do
      it 'returns the webhook event' do
        get api_v1_internal_git_webhook_event_path(webhook_event), headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(webhook_event.id)
        expect(json['data']['event_type']).to eq(webhook_event.event_type)
        expect(json['data']['status']).to eq('pending')
      end

      it 'includes repository information' do
        get api_v1_internal_git_webhook_event_path(webhook_event), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['repository']).to be_present
        expect(json['data']['repository']['id']).to eq(repository.id)
        expect(json['data']['repository']['name']).to eq(repository.name)
      end

      it 'includes provider information' do
        get api_v1_internal_git_webhook_event_path(webhook_event), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['provider']).to be_present
        expect(json['data']['provider']['provider_type']).to eq(git_provider.provider_type)
      end

      it 'includes payload and headers' do
        webhook_event.update!(
          payload: { action: 'opened', number: 123 },
          headers: { 'X-GitHub-Event' => 'pull_request' }
        )

        get api_v1_internal_git_webhook_event_path(webhook_event), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['payload']['action']).to eq('opened')
        expect(json['data']['headers']['X-GitHub-Event']).to eq('pull_request')
      end
    end

    context 'with non-existent webhook event' do
      it 'returns not found' do
        get api_v1_internal_git_webhook_event_path(SecureRandom.uuid), headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Webhook event not found')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_internal_git_webhook_event_path(webhook_event)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/webhook_events/:id' do
    context 'with valid parameters' do
      it 'updates the webhook event' do
        patch api_v1_internal_git_webhook_event_path(webhook_event),
              params: {
                status: 'processed',
                processing_result: { success: true }
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true

        webhook_event.reload
        expect(webhook_event.status).to eq('processed')
        expect(webhook_event.processing_result['success']).to be true
      end

      it 'updates error message' do
        patch api_v1_internal_git_webhook_event_path(webhook_event),
              params: { error_message: 'Processing failed' },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        webhook_event.reload
        expect(webhook_event.error_message).to eq('Processing failed')
      end

      it 'increments retry count' do
        initial_count = webhook_event.retry_count || 0

        patch api_v1_internal_git_webhook_event_path(webhook_event),
              params: { retry_count: initial_count + 1 },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        webhook_event.reload
        expect(webhook_event.retry_count).to eq(initial_count + 1)
      end
    end

    context 'with invalid parameters' do
      it 'returns unprocessable entity' do
        allow_any_instance_of(Devops::GitWebhookEvent).to receive(:update).and_return(false)
        allow_any_instance_of(Devops::GitWebhookEvent).to receive_message_chain(:errors, :full_messages).and_return(['Invalid status'])

        patch api_v1_internal_git_webhook_event_path(webhook_event),
              params: { status: 'invalid' },
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/webhook_events/:id/processing' do
    context 'with pending event' do
      it 'marks event as processing' do
        expect_any_instance_of(Devops::GitWebhookEvent).to receive(:mark_processing!)

        patch processing_api_v1_internal_git_webhook_event_path(webhook_event),
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to have_key('status')
      end
    end

    context 'with non-pending event' do
      it 'returns error' do
        webhook_event.update!(status: 'processing')

        patch processing_api_v1_internal_git_webhook_event_path(webhook_event),
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Event is not pending')
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/webhook_events/:id/processed' do
    context 'with processing event' do
      before { webhook_event.update!(status: 'processing') }

      it 'marks event as processed with result' do
        result = { action: 'completed', items_processed: 5 }

        expect_any_instance_of(Devops::GitWebhookEvent).to receive(:mark_processed!).with(result)

        patch processed_api_v1_internal_git_webhook_event_path(webhook_event),
              params: { processing_result: result },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'handles empty processing result' do
        expect_any_instance_of(Devops::GitWebhookEvent).to receive(:mark_processed!).with({})

        patch processed_api_v1_internal_git_webhook_event_path(webhook_event),
              headers: internal_headers

        expect(response).to have_http_status(:ok)
      end
    end

    context 'with non-processing event' do
      it 'returns error' do
        patch processed_api_v1_internal_git_webhook_event_path(webhook_event),
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Event is not processing')
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/webhook_events/:id/failed' do
    it 'marks event as failed with error message' do
      expect_any_instance_of(Devops::GitWebhookEvent).to receive(:mark_failed!).with('Processing error occurred')

      patch failed_api_v1_internal_git_webhook_event_path(webhook_event),
            params: { error_message: 'Processing error occurred' },
            headers: internal_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end

    it 'uses default error message if not provided' do
      expect_any_instance_of(Devops::GitWebhookEvent).to receive(:mark_failed!).with('Unknown error')

      patch failed_api_v1_internal_git_webhook_event_path(webhook_event),
            headers: internal_headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /api/v1/internal/git/webhook_events/:id/trigger_workflows' do
    let(:workflow) { create(:workflow, account: account) }
    let(:trigger) { create(:workflow_trigger, workflow: workflow) }
    let(:git_workflow_trigger) do
      create(:git_workflow_trigger,
             trigger: trigger,
             repository: repository,
             event_type: webhook_event.event_type,
             is_active: true)
    end

    context 'with matching triggers' do
      before { git_workflow_trigger }

      it 'triggers matching workflows' do
        workflow_run = double('WorkflowRun', run_id: SecureRandom.uuid)
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:trigger!).and_return(workflow_run)
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:matches_event?).and_return(true)

        post trigger_workflows_api_v1_internal_git_webhook_event_path(webhook_event),
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['triggered_count']).to eq(1)
        expect(json['data']['triggered_workflows'].first['workflow_id']).to eq(workflow.id)
      end

      it 'returns workflow execution details' do
        workflow_run = double('WorkflowRun', run_id: 'run-123')
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:trigger!).and_return(workflow_run)
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:matches_event?).and_return(true)

        post trigger_workflows_api_v1_internal_git_webhook_event_path(webhook_event),
             headers: internal_headers

        json = JSON.parse(response.body)
        triggered = json['data']['triggered_workflows'].first
        expect(triggered['git_trigger_id']).to eq(git_workflow_trigger.id)
        expect(triggered['workflow_name']).to eq(workflow.name)
        expect(triggered['run_id']).to eq('run-123')
      end

      it 'continues on trigger errors' do
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:matches_event?).and_return(true)
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:trigger!).and_raise(StandardError.new('Trigger failed'))

        post trigger_workflows_api_v1_internal_git_webhook_event_path(webhook_event),
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['triggered_count']).to eq(0)
      end
    end

    context 'with no matching triggers' do
      it 'returns empty results' do
        post trigger_workflows_api_v1_internal_git_webhook_event_path(webhook_event),
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['triggered_count']).to eq(0)
        expect(json['data']['triggered_workflows']).to be_empty
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post trigger_workflows_api_v1_internal_git_webhook_event_path(webhook_event)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

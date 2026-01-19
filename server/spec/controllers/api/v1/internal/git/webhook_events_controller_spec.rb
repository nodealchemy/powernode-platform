# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Internal::Git::WebhookEventsController, type: :controller do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) { create(:git_repository, :with_webhook, credential: credential, account: account) }
  let(:webhook_event) do
    create(:git_webhook_event,
           repository: repository,
           git_provider: provider,
           account: account,
           event_type: 'push',
           status: 'pending')
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    set_service_auth_headers
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    it 'returns webhook event details' do
      get :show, params: { id: webhook_event.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(webhook_event.id)
      expect(json['data']['event_type']).to eq('push')
      expect(json['data']['status']).to eq('pending')
    end

    it 'includes repository data' do
      get :show, params: { id: webhook_event.id }

      json = JSON.parse(response.body)
      expect(json['data']['repository']['id']).to eq(repository.id)
      expect(json['data']['repository']['full_name']).to eq(repository.full_name)
    end

    it 'includes provider data' do
      get :show, params: { id: webhook_event.id }

      json = JSON.parse(response.body)
      expect(json['data']['provider']['id']).to eq(provider.id)
      expect(json['data']['provider']['provider_type']).to eq('github')
    end

    it 'returns not found for non-existent event' do
      get :show, params: { id: SecureRandom.uuid }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end
  end

  # =============================================================================
  # UPDATE
  # =============================================================================

  describe 'PATCH #update' do
    it 'updates event attributes' do
      patch :update, params: {
        id: webhook_event.id,
        status: 'processed',
        retry_count: 1
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      webhook_event.reload
      expect(webhook_event.retry_count).to eq(1)
    end

    it 'can update processing result' do
      patch :update, params: {
        id: webhook_event.id,
        processing_result: { action: 'synced', items_processed: 5 }
      }

      expect(response).to have_http_status(:success)
      webhook_event.reload
      expect(webhook_event.processing_result['action']).to eq('synced')
    end
  end

  # =============================================================================
  # PROCESSING
  # =============================================================================

  describe 'PATCH #processing' do
    it 'marks event as processing' do
      patch :processing, params: { id: webhook_event.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['status']).to eq('processing')
    end

    context 'when event cannot be processed' do
      before { webhook_event.update!(status: 'processed') }

      it 'returns error' do
        patch :processing, params: { id: webhook_event.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end

  # =============================================================================
  # PROCESSED
  # =============================================================================

  describe 'PATCH #processed' do
    before { webhook_event.update!(status: 'processing') }

    it 'marks event as processed with result' do
      patch :processed, params: {
        id: webhook_event.id,
        processing_result: { commits_synced: 3, pipelines_triggered: 1 }
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['status']).to eq('processed')

      webhook_event.reload
      expect(webhook_event.processing_result['commits_synced']).to eq(3)
    end

    context 'when event is not processing' do
      before { webhook_event.update!(status: 'pending') }

      it 'returns error' do
        patch :processed, params: { id: webhook_event.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # =============================================================================
  # FAILED
  # =============================================================================

  describe 'PATCH #failed' do
    before { webhook_event.update!(status: 'processing') }

    it 'marks event as failed with error message' do
      patch :failed, params: {
        id: webhook_event.id,
        error_message: 'Connection timeout to GitHub API'
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['status']).to eq('failed')

      webhook_event.reload
      expect(webhook_event.error_message).to eq('Connection timeout to GitHub API')
    end

    it 'uses default error message when not provided' do
      patch :failed, params: { id: webhook_event.id }

      webhook_event.reload
      expect(webhook_event.error_message).to eq('Unknown error')
    end
  end

  # =============================================================================
  # AUTHENTICATION
  # =============================================================================

  describe 'authentication' do
    it 'requires service token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :show, params: { id: webhook_event.id }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects invalid service token' do
      @request.env['HTTP_AUTHORIZATION'] = 'Bearer invalid_token'
      get :show, params: { id: webhook_event.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end

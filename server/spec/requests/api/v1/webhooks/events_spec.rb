# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks::Events', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['webhooks.manage']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  let!(:webhook_event) do
    WebhookEvent.create!(
      account: account,
      event_id: SecureRandom.uuid,
      event_type: 'subscription.created',
      provider: 'stripe',
      external_id: "evt_#{SecureRandom.hex(12)}",
      payload: { subscription_id: 'sub_123' }.to_json,
      status: 'pending',
      attempts: 0,
      max_attempts: 5,
      retry_count: 0
    )
  end

  describe 'GET /api/v1/webhooks/events/:id' do
    context 'with proper permissions' do
      it 'returns webhook event details' do
        get "/api/v1/webhooks/events/#{webhook_event.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']).to include(
          'id' => webhook_event.id,
          'event_type' => 'subscription.created',
          'status' => 'pending',
          'account_id' => account.id
        )
        expect(data['webhook_event']).to have_key('payload')
        expect(data['webhook_event']).to have_key('metadata')
      end

      it 'returns not found for non-existent event' do
        get "/api/v1/webhooks/events/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Webhook event not found', 404)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        get "/api/v1/webhooks/events/#{webhook_event.id}", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/webhooks/events/#{webhook_event.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/webhooks/events/:id' do
    let(:update_params) do
      {
        webhook_event: {
          notes: 'Event notes',
          metadata: { key: 'value' }
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the webhook event' do
        patch "/api/v1/webhooks/events/#{webhook_event.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['notes']).to eq('Event notes')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { webhook_event: { notes: 'x' * 50001 } }

        patch "/api/v1/webhooks/events/#{webhook_event.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        patch "/api/v1/webhooks/events/#{webhook_event.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhooks/events/:id/processing' do
    context 'with proper permissions' do
      it 'marks event as processing' do
        post "/api/v1/webhooks/events/#{webhook_event.id}/processing", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('processing')
        expect(data['webhook_event']['attempts']).to eq(1)
        expect(data['message']).to eq('Event marked as processing')

        webhook_event.reload
        expect(webhook_event.status).to eq('processing')
        expect(webhook_event.processing_started_at).to be_present
      end

      it 'returns error when event is not pending' do
        webhook_event.update!(status: 'processed', processed_at: Time.current)

        post "/api/v1/webhooks/events/#{webhook_event.id}/processing", headers: headers, as: :json

        expect_error_response('Event is not pending', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/webhooks/events/#{webhook_event.id}/processing", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhooks/events/:id/processed' do
    let(:processed_params) do
      {
        response_code: 200,
        response_body: 'OK'
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(status: 'processing', processing_started_at: Time.current)
      end

      it 'marks event as processed' do
        post "/api/v1/webhooks/events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('processed')
        expect(data['message']).to eq('Event processed successfully')

        webhook_event.reload
        expect(webhook_event.status).to eq('processed')
        expect(webhook_event.processed_at).to be_present
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        post "/api/v1/webhooks/events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        post "/api/v1/webhooks/events/#{webhook_event.id}/processed", params: processed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhooks/events/:id/failed' do
    let(:failed_params) do
      {
        error: 'Network error',
        response_code: 503,
        response_body: 'Service Unavailable'
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(status: 'processing', attempts: 1)
        allow_any_instance_of(WebhookEvent).to receive(:retriable?).and_return(true)
      end

      it 'marks event for retry when retriable' do
        post "/api/v1/webhooks/events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('pending')
        expect(data['message']).to include('will be retried')

        webhook_event.reload
        expect(webhook_event.last_error).to eq('Network error')
        expect(webhook_event.next_retry_at).to be_present
      end

      it 'marks event as permanently failed when not retriable' do
        allow_any_instance_of(WebhookEvent).to receive(:retriable?).and_return(false)

        post "/api/v1/webhooks/events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('failed')
        expect(data['message']).to include('permanently failed')
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        post "/api/v1/webhooks/events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        post "/api/v1/webhooks/events/#{webhook_event.id}/failed", params: failed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end
end

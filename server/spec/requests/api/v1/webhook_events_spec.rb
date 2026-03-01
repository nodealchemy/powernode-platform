# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::WebhookEvents', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'webhooks.manage' ]) }
  let(:limited_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  let!(:webhook_event) do
    WebhookEvent.create!(
      account: account,
      event_id: SecureRandom.uuid,
      event_type: 'payment.succeeded',
      provider: 'stripe',
      external_id: "evt_#{SecureRandom.hex(12)}",
      payload: { amount: 1000, currency: 'usd' }.to_json,
      occurred_at: Time.current,
      status: 'pending',
      retry_count: 0
    )
  end

  describe 'GET /api/v1/webhook_events/:id' do
    context 'with proper permissions' do
      it 'returns webhook event details' do
        get "/api/v1/webhook_events/#{webhook_event.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']).to include(
          'id' => webhook_event.id,
          'event_type' => 'payment.succeeded',
          'status' => 'pending'
        )
        expect(data['webhook_event']).to have_key('payload')
      end

      it 'returns not found for non-existent event' do
        get "/api/v1/webhook_events/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Webhook event not found', 404)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        get "/api/v1/webhook_events/#{webhook_event.id}", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'PATCH /api/v1/webhook_events/:id' do
    let(:update_params) do
      {
        metadata: { custom_field: 'value' }
      }
    end

    context 'with proper permissions' do
      it 'updates the webhook event metadata' do
        patch "/api/v1/webhook_events/#{webhook_event.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['id']).to eq(webhook_event.id)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        patch "/api/v1/webhook_events/#{webhook_event.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'PATCH /api/v1/webhook_events/:id/processing' do
    context 'with proper permissions' do
      it 'marks event as processing' do
        patch "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('processing')
        expect(data['webhook_event']['retry_count']).to eq(1)

        webhook_event.reload
        expect(webhook_event.status).to eq('processing')
        parsed_metadata = JSON.parse(webhook_event.metadata)
        expect(parsed_metadata['processing_started_at']).to be_present
      end

      it 'returns error when event is not pending' do
        webhook_event.update!(status: 'processed')

        patch "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: headers, as: :json

        expect_error_response('Event is not pending', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        patch "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'PATCH /api/v1/webhook_events/:id/processed' do
    let(:processed_params) do
      {
        response_code: 200
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(
          status: 'processing',
          metadata: { "processing_started_at" => 1.second.ago.iso8601 }.to_json
        )
      end

      it 'marks event as processed' do
        patch "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('processed')

        webhook_event.reload
        expect(webhook_event.status).to eq('processed')
        expect(webhook_event.processed_at).to be_present
        parsed_metadata = JSON.parse(webhook_event.metadata)
        expect(parsed_metadata['delivery_duration_ms']).to be_present
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        patch "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        patch "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'PATCH /api/v1/webhook_events/:id/failed' do
    let(:failed_params) do
      {
        error: 'Connection timeout',
        response_code: 500
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(status: 'processing', retry_count: 1)
      end

      it 'marks event as failed and sets retry for retriable event' do
        patch "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('pending')

        webhook_event.reload
        expect(webhook_event.status).to eq('pending')
        expect(webhook_event.error_message).to eq('Connection timeout')
        parsed_metadata = JSON.parse(webhook_event.metadata)
        expect(parsed_metadata['next_retry_at']).to be_present
      end

      it 'marks event as permanently failed after max attempts' do
        webhook_event.update!(retry_count: 5)

        patch "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('failed')

        webhook_event.reload
        expect(webhook_event.status).to eq('failed')
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        patch "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        patch "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end
end

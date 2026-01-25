# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::WebhookEvents', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['webhooks.manage']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  let!(:webhook_endpoint) { create(:webhook_endpoint, account: account) }
  let!(:webhook_event) do
    WebhookEvent.create!(
      account: account,
      webhook_endpoint_id: webhook_endpoint.id,
      event_id: SecureRandom.uuid,
      event_type: 'payment.succeeded',
      provider: 'stripe',
      external_id: "evt_#{SecureRandom.hex(12)}",
      payload: { amount: 1000, currency: 'usd' }.to_json,
      status: 'pending',
      attempts: 0,
      retry_count: 0
    )
  end

  describe 'GET /api/v1/webhook_events' do
    let!(:webhook_event2) do
      WebhookEvent.create!(
        account: account,
        webhook_endpoint_id: webhook_endpoint.id,
        event_id: SecureRandom.uuid,
        event_type: 'payment.failed',
        provider: 'stripe',
        external_id: "evt_#{SecureRandom.hex(12)}",
        payload: { amount: 500 }.to_json,
        status: 'processed',
        attempts: 1,
        retry_count: 0,
        processed_at: Time.current
      )
    end
    let!(:other_event) do
      WebhookEvent.create!(
        account: other_account,
        event_id: SecureRandom.uuid,
        event_type: 'invoice.paid',
        provider: 'stripe',
        external_id: "evt_#{SecureRandom.hex(12)}",
        payload: {}.to_json,
        status: 'pending',
        attempts: 0,
        retry_count: 0
      )
    end

    context 'with proper permissions' do
      it 'returns list of webhook events for current account' do
        get '/api/v1/webhook_events', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events']).to be_an(Array)
        expect(data['webhook_events'].length).to eq(2)
        expect(data['webhook_events'].none? { |e| e['id'] == other_event.id }).to be true
        expect(data['meta']).to include('total_count' => 2)
      end

      it 'filters by status' do
        get '/api/v1/webhook_events', params: { status: 'pending' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events'].length).to eq(1)
        expect(data['webhook_events'].first['status']).to eq('pending')
      end

      it 'filters by event_type' do
        get '/api/v1/webhook_events', params: { event_type: 'payment.succeeded' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events'].length).to eq(1)
        expect(data['webhook_events'].first['event_type']).to eq('payment.succeeded')
      end

      it 'filters by endpoint_id' do
        get '/api/v1/webhook_events', params: { endpoint_id: webhook_endpoint.id }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events'].length).to eq(2)
      end

      it 'filters by since parameter' do
        past_time = 2.days.ago
        get '/api/v1/webhook_events', params: { since: past_time.iso8601 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events'].length).to eq(2)
      end

      it 'paginates results' do
        get '/api/v1/webhook_events', params: { page: 1, per_page: 1 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_events'].length).to eq(1)
        expect(data['meta']['current_page']).to eq(1)
        expect(data['meta']['per_page']).to eq(1)
        expect(data['meta']['total_count']).to eq(2)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        get '/api/v1/webhook_events', headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/webhook_events', as: :json

        expect_error_response('Access token required', 401)
      end
    end
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
        webhook_event: {
          notes: 'Updated notes',
          metadata: { custom_field: 'value' }
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the webhook event' do
        patch "/api/v1/webhook_events/#{webhook_event.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['notes']).to eq('Updated notes')
      end

      it 'returns validation errors for invalid update' do
        webhook_event.update!(status: 'processed')
        invalid_params = { webhook_event: { notes: 'x' * 10001 } }

        patch "/api/v1/webhook_events/#{webhook_event.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        patch "/api/v1/webhook_events/#{webhook_event.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhook_events/:id/processing' do
    context 'with proper permissions' do
      it 'marks event as processing' do
        post "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: headers, as: :json

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
        webhook_event.update!(status: 'processed')

        post "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: headers, as: :json

        expect_error_response('Event is not pending', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/webhook_events/#{webhook_event.id}/processing", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhook_events/:id/processed' do
    let(:processed_params) do
      {
        response_code: 200,
        response_body: 'Success'
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(status: 'processing', processing_started_at: 1.second.ago)
      end

      it 'marks event as processed' do
        post "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('processed')
        expect(data['webhook_event']['response_code']).to eq(200)
        expect(data['message']).to eq('Event processed successfully')

        webhook_event.reload
        expect(webhook_event.status).to eq('processed')
        expect(webhook_event.processed_at).to be_present
        expect(webhook_event.delivery_duration_ms).to be_present
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        post "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        post "/api/v1/webhook_events/#{webhook_event.id}/processed", params: processed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'POST /api/v1/webhook_events/:id/failed' do
    let(:failed_params) do
      {
        error: 'Connection timeout',
        response_code: 500,
        response_body: 'Internal Server Error'
      }
    end

    context 'with proper permissions' do
      before do
        webhook_event.update!(status: 'processing', attempts: 1)
      end

      it 'marks event as failed and sets retry for retriable event' do
        post "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('pending')
        expect(data['message']).to include('will be retried')

        webhook_event.reload
        expect(webhook_event.status).to eq('pending')
        expect(webhook_event.last_error).to eq('Connection timeout')
        expect(webhook_event.next_retry_at).to be_present
      end

      it 'marks event as permanently failed after max attempts' do
        webhook_event.update!(attempts: 5, max_attempts: 5)

        post "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['webhook_event']['status']).to eq('failed')
        expect(data['message']).to include('permanently failed')

        webhook_event.reload
        expect(webhook_event.status).to eq('failed')
      end

      it 'returns error when event is not processing' do
        webhook_event.update!(status: 'pending')

        post "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: headers, as: :json

        expect_error_response('Event is not processing', 422)
      end
    end

    context 'without webhooks.manage permission' do
      it 'returns forbidden error' do
        webhook_event.update!(status: 'processing')
        post "/api/v1/webhook_events/#{webhook_event.id}/failed", params: failed_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end
end

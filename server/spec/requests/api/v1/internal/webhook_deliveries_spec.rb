# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::WebhookDeliveries', type: :request do
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:account) { create(:account) }
  let(:app) { create(:marketplace_app, account: account) }
  let(:app_webhook) do
    create(:marketplace_app_webhook,
           app: app,
           url: 'https://example.com/webhook',
           headers: { 'X-Custom' => 'value' })
  end
  let!(:webhook_delivery) do
    create(:marketplace_webhook_delivery,
           app_webhook: app_webhook,
           payload: { event: 'test' },
           status: 'pending')
  end

  describe 'GET /api/v1/internal/webhook_deliveries/:id' do
    context 'with valid service token' do
      it 'returns webhook delivery details' do
        get "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(webhook_delivery.id)
        expect(data['webhook_url']).to eq('https://example.com/webhook')
        expect(data['payload']).to eq({ 'event' => 'test' })
        expect(data['headers']).to eq({ 'X-Custom' => 'value' })
        expect(data['attempt']).to eq(webhook_delivery.attempts)
        expect(data['status']).to eq('pending')
      end

      it 'returns empty hash when headers are nil' do
        app_webhook.update(headers: nil)

        get "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        expect(json_response['data']['headers']).to eq({})
      end
    end

    context 'with non-existent webhook delivery' do
      it 'returns not found error' do
        get '/api/v1/internal/webhook_deliveries/non-existent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Webhook delivery not found', 404)
      end
    end

    context 'when standard error occurs' do
      before do
        allow(Marketplace::WebhookDelivery).to receive(:find).and_raise(StandardError.new('Database error'))
      end

      it 'returns internal server error' do
        get "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
            headers: internal_headers,
            as: :json

        expect_error_response('Failed to fetch delivery', 500)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
            as: :json

        expect_error_response('Service token required', 401)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'invalid', type: 'service', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )
        headers = { 'Authorization' => "Bearer #{invalid_token}" }

        get "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
            headers: headers,
            as: :json

        expect_error_response('Invalid service token', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/webhook_deliveries/:id' do
    context 'with valid service token' do
      it 'updates delivery status to in_progress' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'in_progress' },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(webhook_delivery.id)
        expect(data['status']).to eq('in_progress')
        expect(data['message']).to eq('Delivery status updated')

        webhook_delivery.reload
        expect(webhook_delivery.status).to eq('in_progress')
        expect(webhook_delivery.started_at).to be_present
      end

      it 'updates delivery status to delivered' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'delivered' },
              headers: internal_headers,
              as: :json

        expect_success_response
        webhook_delivery.reload
        expect(webhook_delivery.status).to eq('delivered')
        expect(webhook_delivery.delivered_at).to be_present
      end

      it 'updates delivery status to failed' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'failed' },
              headers: internal_headers,
              as: :json

        expect_success_response
        webhook_delivery.reload
        expect(webhook_delivery.status).to eq('failed')
        expect(webhook_delivery.failed_at).to be_present
      end

      it 'updates delivery with metadata' do
        metadata = {
          status_code: 200,
          response_body: 'Success',
          response_time_ms: 150,
          error_message: nil
        }

        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'delivered', metadata: metadata },
              headers: internal_headers,
              as: :json

        expect_success_response
        webhook_delivery.reload
        expect(webhook_delivery.response_code).to eq(200)
        expect(webhook_delivery.response_body).to eq('Success')
        expect(webhook_delivery.response_time_ms).to eq(150)
        expect(webhook_delivery.error_message).to be_nil
      end

      it 'updates delivery with error metadata' do
        metadata = {
          status_code: 500,
          response_body: 'Internal Server Error',
          response_time_ms: 100,
          error_message: 'Connection timeout'
        }

        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'failed', metadata: metadata },
              headers: internal_headers,
              as: :json

        expect_success_response
        webhook_delivery.reload
        expect(webhook_delivery.response_code).to eq(500)
        expect(webhook_delivery.error_message).to eq('Connection timeout')
      end
    end

    context 'with non-existent webhook delivery' do
      it 'returns not found error' do
        patch '/api/v1/internal/webhook_deliveries/non-existent-id',
              params: { status: 'delivered' },
              headers: internal_headers,
              as: :json

        expect_error_response('Webhook delivery not found', 404)
      end
    end

    context 'when standard error occurs' do
      before do
        allow_any_instance_of(Marketplace::WebhookDelivery).to receive(:update!).and_raise(StandardError.new('Update failed'))
      end

      it 'returns internal server error' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'delivered' },
              headers: internal_headers,
              as: :json

        expect_error_response('Failed to update delivery', 500)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}",
              params: { status: 'delivered' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/webhook_deliveries/:id/increment_attempt' do
    context 'with valid service token' do
      it 'increments the attempt counter' do
        initial_attempts = webhook_delivery.attempts

        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}/increment_attempt",
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(webhook_delivery.id)
        expect(data['attempts']).to eq(initial_attempts + 1)
        expect(data['message']).to eq('Attempt incremented')

        webhook_delivery.reload
        expect(webhook_delivery.attempts).to eq(initial_attempts + 1)
      end

      it 'increments multiple times' do
        3.times do
          patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}/increment_attempt",
                headers: internal_headers,
                as: :json

          expect_success_response
        end

        webhook_delivery.reload
        expect(webhook_delivery.attempts).to eq(3)
      end
    end

    context 'with non-existent webhook delivery' do
      it 'returns not found error' do
        patch '/api/v1/internal/webhook_deliveries/non-existent-id/increment_attempt',
              headers: internal_headers,
              as: :json

        expect_error_response('Webhook delivery not found', 404)
      end
    end

    context 'when standard error occurs' do
      before do
        allow_any_instance_of(Marketplace::WebhookDelivery).to receive(:increment!).and_raise(StandardError.new('Increment failed'))
      end

      it 'returns internal server error' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}/increment_attempt",
              headers: internal_headers,
              as: :json

        expect_error_response('Failed to increment attempt', 500)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/webhook_deliveries/#{webhook_delivery.id}/increment_attempt",
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end
end

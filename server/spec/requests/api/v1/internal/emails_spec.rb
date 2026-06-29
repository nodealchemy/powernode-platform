# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Emails', type: :request do
  # Worker authentication via InternalBaseController (mTLS CN = node_instance_id)
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  before do
    # The send mechanism (worker enqueue) is stubbed so specs assert the
    # server-side ledger + dispatch without real HTTP to the worker.
    allow(WorkerJobService).to receive(:enqueue_alert_email)
  end

  describe 'POST /api/v1/internal/emails/security_alert' do
    let(:valid_params) do
      {
        recipient: 'security@example.com',
        alert_type: 'suspicious_activity',
        details: { ip_address: '192.168.1.100', location: 'Unknown' },
        severity: 'high'
      }
    end

    context 'with internal authentication' do
      it 'creates a pending EmailDelivery ledger row' do
        expect {
          post '/api/v1/internal/emails/security_alert',
               params: valid_params, headers: internal_headers, as: :json
        }.to change(EmailDelivery, :count).by(1)

        expect_success_response
        delivery = EmailDelivery.last
        expect(delivery.status).to eq('pending')
        expect(delivery.recipient_email).to eq('security@example.com')
        expect(delivery.email_type).to eq('notification')
        expect(delivery.subject).to eq('Security Alert: suspicious_activity')
        expect(delivery.metadata['category']).to eq('security_alert')
        expect(delivery.metadata['alert_type']).to eq('suspicious_activity')

        data = json_response_data
        expect(data['message']).to include('Security alert email queued')
        expect(data['email_delivery_id']).to eq(delivery.id)
      end

      it 'enqueues the worker send job with the pending ledger id' do
        post '/api/v1/internal/emails/security_alert',
             params: valid_params, headers: internal_headers, as: :json

        delivery = EmailDelivery.last
        expect(WorkerJobService).to have_received(:enqueue_alert_email).with(
          hash_including(email_delivery_id: delivery.id, recipient: 'security@example.com')
        )
      end

      it 'records the ledger row as failed when the worker enqueue fails' do
        allow(WorkerJobService).to receive(:enqueue_alert_email)
          .and_raise(WorkerJobService::WorkerServiceError, 'worker unavailable')

        post '/api/v1/internal/emails/security_alert',
             params: valid_params, headers: internal_headers, as: :json

        # Worker-receiver discipline: still 2xx, but the ledger reflects the
        # real failed hand-off (no fabricated success).
        expect_success_response
        expect(EmailDelivery.last.status).to eq('failed')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/emails/security_alert', params: valid_params, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        post '/api/v1/internal/emails/security_alert',
             params: valid_params,
             headers: { 'Authorization' => "Bearer #{invalid_token}" },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/emails/review_notification' do
    let(:valid_params) do
      {
        recipient: 'reviewer@example.com',
        subject: 'Review Required: New submission',
        body: 'Please review the attached submission',
        review_id: SecureRandom.uuid
      }
    end

    context 'with internal authentication' do
      it 'creates a pending EmailDelivery and enqueues the send' do
        expect {
          post '/api/v1/internal/emails/review_notification',
               params: valid_params, headers: internal_headers, as: :json
        }.to change(EmailDelivery, :count).by(1)

        expect_success_response
        delivery = EmailDelivery.last
        expect(delivery.status).to eq('pending')
        expect(delivery.recipient_email).to eq('reviewer@example.com')
        expect(delivery.metadata['category']).to eq('review_notification')

        expect(json_response_data['message']).to include('Review notification email queued')
        expect(WorkerJobService).to have_received(:enqueue_alert_email).with(
          hash_including(email_delivery_id: delivery.id, subject: 'Review Required: New submission')
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/emails/review_notification', params: valid_params, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/emails/:id/delivered' do
    let(:delivery) { create(:email_delivery, status: 'pending') }

    context 'when the worker reports a successful send' do
      it 'moves the ledger row to sent and records the message id' do
        post "/api/v1/internal/emails/#{delivery.id}/delivered",
             params: { status: 'sent', message_id: 'abc123@mail' },
             headers: internal_headers, as: :json

        expect_success_response
        delivery.reload
        expect(delivery.status).to eq('sent')
        expect(delivery.sent_at).to be_present
        expect(delivery.external_id).to eq('abc123@mail')
      end
    end

    context 'when the worker reports a failed send' do
      it 'records the ledger row as failed with the error message' do
        post "/api/v1/internal/emails/#{delivery.id}/delivered",
             params: { status: 'failed', error: 'SMTP connection refused' },
             headers: internal_headers, as: :json

        expect_success_response
        delivery.reload
        expect(delivery.status).to eq('failed')
        expect(delivery.error_message).to eq('SMTP connection refused')
      end
    end

    context 'when the delivery id is unknown' do
      it 'returns 2xx without raising (idempotent callback)' do
        post "/api/v1/internal/emails/#{SecureRandom.uuid}/delivered",
             params: { status: 'sent' }, headers: internal_headers, as: :json

        expect(response).to have_http_status(:success)
        expect(json_response_data['applied']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/emails/#{delivery.id}/delivered",
             params: { status: 'sent' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end

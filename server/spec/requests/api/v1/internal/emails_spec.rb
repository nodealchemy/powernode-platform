# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Emails', type: :request do
  # Worker JWT authentication via InternalBaseController
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
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
      it 'queues review notification email' do
        post '/api/v1/internal/emails/review_notification',
             params: valid_params,
             headers: internal_headers,
             as: :json

        expect_success_response
        # render_success(message: "Review notification email queued")
        # produces { success: true, data: { message: "..." } }
        data = json_response_data

        expect(data['message']).to include('Review notification email queued')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/emails/review_notification',
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/emails/security_alert' do
    let(:valid_params) do
      {
        recipient: 'security@example.com',
        alert_type: 'suspicious_activity',
        details: {
          ip_address: '192.168.1.100',
          location: 'Unknown',
          timestamp: Time.current.iso8601
        }
      }
    end

    context 'with internal authentication' do
      it 'queues security alert email' do
        post '/api/v1/internal/emails/security_alert',
             params: valid_params,
             headers: internal_headers,
             as: :json

        expect_success_response
        # render_success(message: "Security alert email queued")
        # produces { success: true, data: { message: "..." } }
        data = json_response_data

        expect(data['message']).to include('Security alert email queued')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/emails/security_alert',
             params: valid_params,
             as: :json

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
end

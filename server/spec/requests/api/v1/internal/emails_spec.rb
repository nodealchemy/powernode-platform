# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Emails', type: :request do
  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
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
        response_data = json_response

        expect(response_data['message']).to include('Review notification email queued')
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
        response_data = json_response

        expect(response_data['message']).to include('Security alert email queued')
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

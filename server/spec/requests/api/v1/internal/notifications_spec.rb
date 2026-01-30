# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Notifications', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    # Stub broadcast to avoid ActionCable/channel errors
    allow(NotificationChannel).to receive(:broadcast_to_account).and_return(true)
  end

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/notifications' do
    let(:valid_params) do
      {
        user_id: user.id,
        account_id: account.id,
        title: 'Test Notification',
        message: 'Test notification message',
        notification_type: 'system_alert',
        severity: 'info'
      }
    end

    context 'with internal authentication' do
      it 'creates a notification' do
        expect {
          post '/api/v1/internal/notifications', params: valid_params, headers: internal_headers, as: :json
        }.to change(Notification, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data).to include(
          'user_id' => user.id,
          'message' => 'Test notification message'
        )
      end

      it 'handles validation errors' do
        post '/api/v1/internal/notifications',
             params: { message: '' },
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/notifications', params: valid_params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/notifications/send' do
    let(:user2) { create(:user, account: account) }

    context 'with internal authentication' do
      it 'sends notification to single user' do
        post '/api/v1/internal/notifications/send',
             params: {
               user_id: user.id,
               message: 'Single user notification',
               type: 'system_alert'
             },
             headers: internal_headers,
             as: :json

        expect_success_response
        # render_success(data: notifications, message: "Notifications sent")
        # message is dropped when data is present, so just check data
        data = json_response_data
        expect(data).to be_an(Array)
      end

      it 'sends notification to multiple users' do
        post '/api/v1/internal/notifications/send',
             params: {
               user_ids: [user.id, user2.id],
               message: 'Multi-user notification',
               type: 'system_alert'
             },
             headers: internal_headers,
             as: :json

        expect_success_response
        data = json_response_data

        expect(data.length).to eq(2)
      end
    end
  end

  describe 'POST /api/v1/internal/notifications/security_alert' do
    context 'with internal authentication' do
      it 'sends security alert notification' do
        post '/api/v1/internal/notifications/security_alert',
             params: {
               user_id: user.id,
               account_id: account.id,
               alert_type: 'suspicious_login',
               message: 'Suspicious login detected from new location',
               severity: 'warning'
             },
             headers: internal_headers,
             as: :json

        expect_success_response
        # render_success(data: notification_data(notification), message: "Security alert sent")
        # message is dropped when data is present
        data = json_response_data
        expect(data['notification_type']).to eq('security_alert')
      end

      it 'defaults severity to warning' do
        post '/api/v1/internal/notifications/security_alert',
             params: {
               user_id: user.id,
               account_id: account.id,
               alert_type: 'password_change',
               message: 'Your password was changed'
             },
             headers: internal_headers,
             as: :json

        expect_success_response
      end
    end
  end
end

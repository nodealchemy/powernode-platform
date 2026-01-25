# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::ReviewNotifications', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:recipient) { create(:user, account: account) }
  let(:app) { create(:app, account: account, user: user) }
  let(:review) { create(:review, app: app, user: user) }
  let(:notification) { create(:review_notification, review: review, recipient: recipient) }

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/review_notifications/:id' do
    context 'with internal authentication' do
      it 'returns notification details' do
        get "/api/v1/internal/review_notifications/#{notification.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['id']).to eq(notification.id)
        expect(response_data['data']['data']['status']).to eq(notification.status)
      end

      it 'includes recipient information' do
        get "/api/v1/internal/review_notifications/#{notification.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['recipient_email']).to eq(recipient.email)
        expect(response_data['data']['data']['recipient_name']).to eq(recipient.name)
      end

      it 'includes review information' do
        get "/api/v1/internal/review_notifications/#{notification.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        review_data = response_data['data']['data']['review']
        expect(review_data['id']).to eq(review.id)
        expect(review_data['rating']).to eq(review.rating)
        expect(review_data['title']).to eq(review.title)
        expect(review_data['comment']).to eq(review.comment)
        expect(review_data['author_name']).to eq(user.name)
      end

      it 'includes app information' do
        get "/api/v1/internal/review_notifications/#{notification.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        response_data = json_response

        app_data = response_data['data']['data']['app']
        expect(app_data['id']).to eq(app.id)
        expect(app_data['name']).to eq(app.name)
        expect(app_data['description']).to eq(app.description)
      end
    end

    context 'when notification does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/review_notifications/nonexistent-id',
            headers: internal_headers,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/review_notifications/#{notification.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/review_notifications/:id' do
    context 'with internal authentication' do
      it 'updates notification status to sent' do
        sent_time = Time.current

        patch "/api/v1/internal/review_notifications/#{notification.id}",
              headers: internal_headers,
              params: { status: 'sent', sent_at: sent_time },
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['status']).to eq('sent')
        expect(response_data['data']['message']).to eq('Notification status updated')

        notification.reload
        expect(notification.status).to eq('sent')
        expect(notification.sent_at).to be_within(1.second).of(sent_time)
      end

      it 'updates notification status to failed with error message' do
        error_msg = 'Email delivery failed: SMTP timeout'

        patch "/api/v1/internal/review_notifications/#{notification.id}",
              headers: internal_headers,
              params: { status: 'failed', error_message: error_msg },
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['status']).to eq('failed')

        notification.reload
        expect(notification.status).to eq('failed')
        expect(notification.error_message).to eq(error_msg)
      end

      it 'uses current time for sent_at if not provided' do
        freeze_time do
          patch "/api/v1/internal/review_notifications/#{notification.id}",
                headers: internal_headers,
                params: { status: 'sent' },
                as: :json

          expect_success_response

          notification.reload
          expect(notification.sent_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'returns notification id and status in response' do
        patch "/api/v1/internal/review_notifications/#{notification.id}",
              headers: internal_headers,
              params: { status: 'sent' },
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to include(
          'id' => notification.id,
          'status' => 'sent',
          'message' => 'Notification status updated'
        )
      end
    end

    context 'when notification does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/review_notifications/nonexistent-id',
              headers: internal_headers,
              params: { status: 'sent' },
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

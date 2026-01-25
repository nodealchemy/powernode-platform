# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Notifications', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  # Helper to create notification
  let(:create_notification) do
    ->(attrs = {}) {
      Notification.create!({
        user: user,
        account: account,
        title: 'Test Notification',
        message: 'This is a test notification',
        notification_type: 'info',
        severity: 'info',
        category: 'general',
        read_at: nil,
        dismissed_at: nil
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/notifications' do
    before do
      create_notification.call
      create_notification.call(title: 'Second', read_at: Time.current)
      create_notification.call(title: 'Third', category: 'system')
    end

    context 'with authentication' do
      it 'returns user notifications' do
        get '/api/v1/notifications', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['notifications']).to be_an(Array)
        expect(response_data['data']).to have_key('unread_count')
        expect(response_data['data']).to have_key('pagination')
      end

      it 'filters unread notifications' do
        get '/api/v1/notifications', params: { unread: 'true' }, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        response_data['data']['notifications'].each do |notification|
          expect(notification['read']).to be false
        end
      end

      it 'filters by category' do
        get '/api/v1/notifications', params: { category: 'system' }, headers: headers, as: :json

        expect_success_response
      end

      it 'paginates results' do
        get '/api/v1/notifications', params: { page: 1, per_page: 2 }, headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['pagination']['per_page']).to eq(2)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/notifications', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/notifications/unread_count' do
    before do
      create_notification.call
      create_notification.call(read_at: Time.current)
    end

    it 'returns unread count' do
      get '/api/v1/notifications/unread_count', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('unread_count')
      expect(response_data['data']['unread_count']).to be >= 1
    end
  end

  describe 'GET /api/v1/notifications/:id' do
    let(:notification) { create_notification.call }

    it 'returns notification details' do
      get "/api/v1/notifications/#{notification.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to include(
        'id' => notification.id,
        'title' => notification.title
      )
    end

    context 'when notification does not exist' do
      it 'returns not found error' do
        get '/api/v1/notifications/nonexistent-id', headers: headers, as: :json

        expect_error_response('Notification not found', 404)
      end
    end
  end

  describe 'PUT /api/v1/notifications/:id/read' do
    let(:notification) { create_notification.call }

    it 'marks notification as read' do
      allow_any_instance_of(Notification).to receive(:mark_as_read!).and_return(true)

      put "/api/v1/notifications/#{notification.id}/read", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('marked as read')
    end
  end

  describe 'PUT /api/v1/notifications/:id/unread' do
    let(:notification) { create_notification.call(read_at: Time.current) }

    it 'marks notification as unread' do
      allow_any_instance_of(Notification).to receive(:mark_as_unread!).and_return(true)

      put "/api/v1/notifications/#{notification.id}/unread", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('marked as unread')
    end
  end

  describe 'POST /api/v1/notifications/mark_all_read' do
    before do
      create_notification.call
      create_notification.call
    end

    it 'marks all notifications as read' do
      post '/api/v1/notifications/mark_all_read', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('marked as read')
      expect(response_data['data']).to have_key('marked_count')
    end
  end

  describe 'DELETE /api/v1/notifications/:id' do
    let(:notification) { create_notification.call }

    it 'dismisses notification' do
      allow_any_instance_of(Notification).to receive(:dismiss!).and_return(true)

      delete "/api/v1/notifications/#{notification.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('dismissed')
    end
  end

  describe 'DELETE /api/v1/notifications/dismiss_all' do
    before do
      create_notification.call
      create_notification.call
    end

    it 'dismisses all notifications' do
      delete '/api/v1/notifications/dismiss_all', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['message']).to include('dismissed')
      expect(response_data['data']).to have_key('dismissed_count')
    end
  end
end

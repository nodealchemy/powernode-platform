# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppWebhooks', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['apps.read', 'apps.update', 'apps.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/apps/:app_id/webhooks' do
    let!(:webhooks) do
      [
        create(:app_webhook, app: app, name: 'User Created', event_type: 'user.created', is_active: true),
        create(:app_webhook, app: app, name: 'User Updated', event_type: 'user.updated', is_active: true),
        create(:app_webhook, app: app, name: 'User Deleted', event_type: 'user.deleted', is_active: false)
      ]
    end

    context 'with apps.read permission' do
      it 'returns all webhooks for the app' do
        get "/api/v1/apps/#{app.id}/webhooks", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(3)
      end

      it 'filters by event_type' do
        get "/api/v1/apps/#{app.id}/webhooks?event_type=user.created", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['event_type']).to eq('user.created')
      end

      it 'filters by active status' do
        get "/api/v1/apps/#{app.id}/webhooks?active=true", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(2)
        expect(data.all? { |w| w['is_active'] }).to be true
      end

      it 'includes pagination metadata' do
        get "/api/v1/apps/#{app.id}/webhooks", headers: headers, as: :json

        expect_success_response
        expect(json_response['meta']['pagination']).to be_present
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/webhooks", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end

    context 'with non-existent app' do
      it 'returns not found error' do
        get "/api/v1/apps/non-existent-id/webhooks", headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/webhooks/:id' do
    let(:webhook) { create(:app_webhook, app: app) }

    context 'with apps.read permission' do
      it 'returns the webhook with analytics' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['id']).to eq(webhook.id)
        expect(data['name']).to eq(webhook.name)
        expect(data).to have_key('analytics')
      end

      it 'includes webhook details' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'id',
          'name',
          'slug',
          'event_type',
          'url',
          'http_method',
          'is_active',
          'secret_token'
        )
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end

    context 'with non-existent webhook' do
      it 'returns not found error' do
        get "/api/v1/apps/#{app.id}/webhooks/non-existent-id", headers: headers, as: :json

        expect_error_response('Webhook not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/webhooks' do
    let(:valid_params) do
      {
        app_webhook: {
          name: 'Order Created',
          slug: 'order-created',
          event_type: 'order.created',
          url: 'https://example.com/webhooks/orders',
          http_method: 'POST',
          is_active: true
        }
      }
    end

    context 'with apps.update permission' do
      it 'creates a new webhook' do
        expect do
          post "/api/v1/apps/#{app.id}/webhooks", params: valid_params, headers: headers, as: :json
        end.to change(app.app_webhooks, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Order Created')
        expect(json_response['message']).to eq('Webhook created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_webhook: { name: '' } }
        post "/api/v1/apps/#{app.id}/webhooks", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/webhooks", params: valid_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'PUT /api/v1/apps/:app_id/webhooks/:id' do
    let(:webhook) { create(:app_webhook, app: app, name: 'Old Name') }
    let(:update_params) do
      {
        app_webhook: {
          name: 'New Name'
        }
      }
    end

    context 'with apps.update permission' do
      it 'updates the webhook' do
        put "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('New Name')
        expect(json_response['message']).to eq('Webhook updated successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_webhook: { name: '' } }
        put "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        put "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", params: update_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'DELETE /api/v1/apps/:app_id/webhooks/:id' do
    let!(:webhook) { create(:app_webhook, app: app) }

    context 'with apps.delete permission' do
      it 'deletes the webhook' do
        expect do
          delete "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", headers: headers, as: :json
        end.to change(app.app_webhooks, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('Webhook deleted successfully')
      end
    end

    context 'without apps.delete permission' do
      let(:user_without_delete) { create(:user, account: account, permissions: ['apps.read', 'apps.update']) }

      it 'returns forbidden error' do
        delete "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}", headers: auth_headers_for(user_without_delete), as: :json

        expect_error_response('Permission denied: apps.delete', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/webhooks/:id/activate' do
    let(:webhook) { create(:app_webhook, app: app, is_active: false) }

    context 'with apps.update permission' do
      it 'activates the webhook' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/activate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be true
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/activate", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/webhooks/:id/deactivate' do
    let(:webhook) { create(:app_webhook, app: app, is_active: true) }

    context 'with apps.update permission' do
      it 'deactivates the webhook' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/deactivate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be false
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/deactivate", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/webhooks/:id/test' do
    let(:webhook) { create(:app_webhook, app: app) }
    let(:test_params) do
      {
        test_data: { event: 'test', timestamp: Time.current.iso8601 }
      }
    end

    context 'with apps.update permission' do
      it 'initiates test delivery' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/test", params: test_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'delivery_id',
          'event_id',
          'status',
          'payload'
        )
        expect(json_response['message']).to eq('Test webhook delivery initiated')
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/test", params: test_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/webhooks/:id/regenerate_secret' do
    let(:webhook) { create(:app_webhook, app: app) }

    context 'with apps.update permission' do
      it 'regenerates the secret token' do
        old_secret = webhook.secret_token
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/regenerate_secret", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['secret_token']).to be_present
        expect(data['secret_token']).not_to eq(old_secret)
        expect(json_response['message']).to eq('Webhook secret token regenerated successfully')
      end
    end

    context 'without apps.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/regenerate_secret", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.update', 403)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/webhooks/:id/deliveries' do
    let(:webhook) { create(:app_webhook, app: app) }

    before do
      create_list(:app_webhook_delivery, 5, app_webhook: webhook)
    end

    context 'with apps.read permission' do
      it 'returns webhook deliveries' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/deliveries", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(5)
        expect(data.first).to include(
          'id',
          'delivery_id',
          'event_id',
          'status',
          'status_code'
        )
      end

      it 'filters by status' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/deliveries?status=success", headers: headers, as: :json

        expect_success_response
      end

      it 'includes pagination metadata' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/deliveries", headers: headers, as: :json

        expect_success_response
        expect(json_response['meta']['pagination']).to be_present
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/webhooks/:id/analytics' do
    let(:webhook) { create(:app_webhook, app: app) }

    before do
      create_list(:app_webhook_delivery, 10, app_webhook: webhook)
    end

    context 'with apps.read permission' do
      it 'returns analytics data' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/analytics", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'total_deliveries',
          'deliveries_by_day',
          'deliveries_by_status',
          'success_rate',
          'failure_rate',
          'average_response_time'
        )
      end

      it 'respects days parameter' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/analytics?days=7", headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without apps.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/webhooks/#{webhook.id}/analytics", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Permission denied: apps.read', 403)
      end
    end
  end
end

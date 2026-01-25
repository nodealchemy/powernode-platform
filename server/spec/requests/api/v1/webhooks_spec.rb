# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks', type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_webhook_permission) { create(:user, account: account, permissions: ['webhook.view', 'webhook.create', 'webhook.update', 'webhook.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  before do
    create(:subscription, :active, account: account, plan: plan)
  end

  describe 'GET /api/v1/webhooks' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    before do
      create_list(:webhook_endpoint, 5, created_by: admin_user)
    end

    context 'with webhook.view permission' do
      it 'returns paginated list of webhooks' do
        get '/api/v1/webhooks', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['webhooks']).to be_an(Array)
        expect(response_data['data']['webhooks'].length).to eq(5)
      end

      it 'includes pagination metadata' do
        get '/api/v1/webhooks', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include(
          'current_page' => 1,
          'total_count' => 5
        )
      end

      it 'includes webhook stats' do
        get '/api/v1/webhooks', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['stats']).to include(
          'total_endpoints',
          'active_endpoints'
        )
      end

      it 'respects per_page parameter' do
        get '/api/v1/webhooks', params: { per_page: 2 }, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['webhooks'].length).to eq(2)
      end
    end

    context 'without webhook.view permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/webhooks', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/webhooks', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/webhooks/:id' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, created_by: admin_user) }

    context 'with webhook.view permission' do
      it 'returns webhook details' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => webhook.id,
          'url' => webhook.url
        )
      end

      it 'includes secret_token in detailed view' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('secret_token')
      end

      it 'includes recent_deliveries' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('recent_deliveries')
      end

      it 'includes delivery_stats' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('delivery_stats')
      end
    end

    context 'when webhook does not exist' do
      it 'returns not found error' do
        get '/api/v1/webhooks/nonexistent-id', headers: headers, as: :json

        expect_error_response('Webhook endpoint not found', 404)
      end
    end
  end

  describe 'POST /api/v1/webhooks' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    context 'with webhook.create permission' do
      let(:valid_params) do
        {
          webhook: {
            url: 'https://example.com/webhook',
            description: 'Test webhook',
            event_types: ['user.created', 'user.updated']
          }
        }
      end

      it 'creates a new webhook' do
        expect {
          post '/api/v1/webhooks', params: valid_params, headers: headers, as: :json
        }.to change(WebhookEndpoint, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['url']).to eq('https://example.com/webhook')
      end

      it 'sets created_by to current user' do
        post '/api/v1/webhooks', params: valid_params, headers: headers, as: :json

        webhook = WebhookEndpoint.last
        expect(webhook.created_by).to eq(user_with_webhook_permission)
      end

      it 'creates audit log for webhook creation' do
        expect {
          post '/api/v1/webhooks', params: valid_params, headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'webhook_created')
        expect(audit_log).to be_present
      end
    end

    context 'with invalid data' do
      it 'returns validation error for invalid URL' do
        post '/api/v1/webhooks',
             params: { webhook: { url: 'not-a-url' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without webhook.create permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        post '/api/v1/webhooks',
             params: { webhook: { url: 'https://example.com' } },
             headers: headers,
             as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'PUT /api/v1/webhooks/:id' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, created_by: admin_user) }

    context 'with webhook.update permission' do
      it 'updates webhook successfully' do
        put "/api/v1/webhooks/#{webhook.id}",
            params: { webhook: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        webhook.reload
        expect(webhook.description).to eq('Updated description')
      end

      it 'updates event_types' do
        put "/api/v1/webhooks/#{webhook.id}",
            params: { webhook: { event_types: ['payment.completed'] } },
            headers: headers,
            as: :json

        expect_success_response

        webhook.reload
        expect(webhook.event_types).to include('payment.completed')
      end
    end

    context 'without webhook.update permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        put "/api/v1/webhooks/#{webhook.id}",
            params: { webhook: { description: 'Hacked' } },
            headers: headers,
            as: :json

        expect_error_response('Permission denied', 403)
      end
    end
  end

  describe 'DELETE /api/v1/webhooks/:id' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, created_by: admin_user) }

    context 'with webhook.delete permission' do
      it 'deletes webhook successfully' do
        webhook_id = webhook.id

        delete "/api/v1/webhooks/#{webhook_id}", headers: headers, as: :json

        expect_success_response
        expect(WebhookEndpoint.find_by(id: webhook_id)).to be_nil
      end

      it 'creates audit log for deletion' do
        expect {
          delete "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'webhook_deleted')
        expect(audit_log).to be_present
      end
    end
  end

  describe 'POST /api/v1/webhooks/:id/test' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, created_by: admin_user) }

    before do
      allow(WebhookService).to receive(:deliver_webhook).and_return({
        success: true,
        status: 200,
        response_time: 150
      })
    end

    it 'sends test webhook successfully' do
      post "/api/v1/webhooks/#{webhook.id}/test", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to include('webhook_id', 'test_payload', 'response')
    end

    it 'accepts custom event_type' do
      post "/api/v1/webhooks/#{webhook.id}/test",
           params: { event_type: 'custom.event' },
           headers: headers,
           as: :json

      expect_success_response
    end

    it 'creates audit log for test' do
      expect {
        post "/api/v1/webhooks/#{webhook.id}/test", headers: headers, as: :json
      }.to change(AuditLog, :count).by_at_least(1)
    end
  end

  describe 'POST /api/v1/webhooks/:id/toggle_status' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, status: 'active', created_by: admin_user) }

    context 'with webhook.update permission' do
      it 'toggles from active to inactive' do
        post "/api/v1/webhooks/#{webhook.id}/toggle_status", headers: headers, as: :json

        expect_success_response

        webhook.reload
        expect(webhook.status).to eq('inactive')
      end

      it 'toggles from inactive to active' do
        webhook.update!(status: 'inactive')

        post "/api/v1/webhooks/#{webhook.id}/toggle_status", headers: headers, as: :json

        expect_success_response

        webhook.reload
        expect(webhook.status).to eq('active')
      end
    end
  end

  describe 'GET /api/v1/webhooks/events' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns available event types' do
      get '/api/v1/webhooks/events', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('events')
      expect(response_data['data']).to have_key('categories')
    end
  end

  describe 'GET /api/v1/webhooks/deliveries' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns delivery history' do
      get '/api/v1/webhooks/deliveries', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('deliveries')
      expect(response_data['data']).to have_key('pagination')
    end

    it 'filters by webhook_id' do
      webhook = create(:webhook_endpoint, created_by: admin_user)

      get '/api/v1/webhooks/deliveries',
          params: { webhook_id: webhook.id },
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/webhooks/stats' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns detailed webhook stats' do
      get '/api/v1/webhooks/stats', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to include(
        'total_endpoints',
        'active_endpoints'
      )
    end
  end

  describe 'GET /api/v1/webhooks/failed_deliveries' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns failed deliveries' do
      get '/api/v1/webhooks/failed_deliveries', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('deliveries')
      expect(response_data['data']).to have_key('summary')
    end

    it 'includes summary statistics' do
      get '/api/v1/webhooks/failed_deliveries', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['summary']).to include(
        'failed_count',
        'max_retries_count'
      )
    end
  end

  describe 'GET /api/v1/webhooks/health' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns webhook health check data' do
      get '/api/v1/webhooks/health', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/webhooks/:id/health_test' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, created_by: admin_user) }

    it 'performs health test on webhook' do
      allow_any_instance_of(WebhookHealthService).to receive(:test_endpoint).and_return({
        success: true,
        response_time: 100,
        status_code: 200
      })

      post "/api/v1/webhooks/#{webhook.id}/health_test", headers: headers, as: :json

      expect_success_response
    end
  end
end

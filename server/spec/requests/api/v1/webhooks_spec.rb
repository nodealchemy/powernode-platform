# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Webhooks', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_webhook_permission) { create(:user, account: account, permissions: [ 'webhook.read', 'webhook.create', 'webhook.update', 'webhook.delete' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'cross-account isolation (IDOR)' do
    let(:other_account) { create(:account) }
    let!(:own_webhook) { create(:webhook_endpoint, account: account, created_by: admin_user) }
    let!(:foreign_webhook) { create(:webhook_endpoint, account: other_account) }
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'index only lists endpoints belonging to the requesting account' do
      get '/api/v1/webhooks', headers: headers, as: :json

      expect_success_response
      ids = json_response['data']['webhooks'].map { |w| w['id'] }
      expect(ids).to include(own_webhook.id)
      expect(ids).not_to include(foreign_webhook.id)
      expect(json_response['data']['pagination']['total_count']).to eq(1)
    end

    it 'index stats count only the requesting account endpoints' do
      get '/api/v1/webhooks', headers: headers, as: :json

      expect(json_response['data']['stats']['total_endpoints']).to eq(1)
    end

    it 'show returns 404 for a foreign-account endpoint' do
      get "/api/v1/webhooks/#{foreign_webhook.id}", headers: headers, as: :json

      expect_error_response('Webhook endpoint not found', 404)
    end

    it 'never leaks a foreign-account secret_key' do
      get "/api/v1/webhooks/#{foreign_webhook.id}", headers: headers, as: :json

      expect(response.body).not_to include(foreign_webhook.secret_key.to_s) if foreign_webhook.secret_key.present?
      expect(json_response['data']).to be_nil.or(satisfy { |d| !d.key?('secret_key') })
    end

    it 'allows access to an own-account endpoint and exposes its secret_key' do
      get "/api/v1/webhooks/#{own_webhook.id}", headers: headers, as: :json

      expect_success_response
      expect(json_response['data']['id']).to eq(own_webhook.id)
      expect(json_response['data']).to have_key('secret_key')
    end

    context 'delivery_history / failed_deliveries / stats (cross-account read)' do
      let!(:own_delivery) { create(:webhook_delivery, :failed, webhook_endpoint: own_webhook) }
      let!(:foreign_delivery) { create(:webhook_delivery, :failed, webhook_endpoint: foreign_webhook) }

      it 'delivery_history returns only the requesting account deliveries' do
        get '/api/v1/webhooks/deliveries', headers: headers, as: :json
        expect_success_response
        expect(response.body).to include(own_delivery.id)
        expect(response.body).not_to include(foreign_delivery.id)
      end

      it 'failed_deliveries returns only the requesting account deliveries' do
        get '/api/v1/webhooks/failed_deliveries', headers: headers, as: :json
        expect_success_response
        expect(response.body).to include(own_delivery.id)
        expect(response.body).not_to include(foreign_delivery.id)
      end

      it 'stats never expose a foreign endpoint URL' do
        get '/api/v1/webhooks/stats', headers: headers, as: :json
        expect_success_response
        expect(response.body).not_to include(foreign_webhook.url.to_s) if foreign_webhook.url.present?
      end

      it 'delivery_history requires webhook.read' do
        get '/api/v1/webhooks/deliveries', headers: auth_headers_for(regular_user), as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'retry_delivery (IDOR + authz)' do
      let!(:own_delivery) { create(:webhook_delivery, :failed, webhook_endpoint: own_webhook) }
      let!(:foreign_delivery) { create(:webhook_delivery, :failed, webhook_endpoint: foreign_webhook) }

      it 'returns 404 when retrying a foreign-account delivery and does not requeue it' do
        post "/api/v1/webhooks/#{foreign_webhook.id}/deliveries/#{foreign_delivery.id}/retry",
             headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        # Foreign delivery must remain untouched (not reset to pending).
        expect(foreign_delivery.reload.status).to eq('failed')
      end

      it 'returns 404 when crossing a foreign delivery id into an own endpoint' do
        post "/api/v1/webhooks/#{own_webhook.id}/deliveries/#{foreign_delivery.id}/retry",
             headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect(foreign_delivery.reload.status).to eq('failed')
      end

      it 'requires the webhook.update permission' do
        post "/api/v1/webhooks/#{own_webhook.id}/deliveries/#{own_delivery.id}/retry",
             headers: auth_headers_for(regular_user), as: :json

        expect(response).to have_http_status(:forbidden)
      end

      it 'retries an own-account delivery with permission' do
        post "/api/v1/webhooks/#{own_webhook.id}/deliveries/#{own_delivery.id}/retry",
             headers: headers, as: :json

        expect_success_response
        expect(own_delivery.reload.status).to eq('pending')
      end
    end
  end

  describe 'GET /api/v1/webhooks' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    before do
      create_list(:webhook_endpoint, 5, account: account, created_by: admin_user)
    end

    context 'with webhook.read permission' do
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
        get '/api/v1/webhooks?per_page=2', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['webhooks'].length).to eq(2)
      end
    end

    context 'without webhook.read permission' do
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
    let(:webhook) { create(:webhook_endpoint, account: account, created_by: admin_user) }

    context 'with webhook.read permission' do
      it 'returns webhook details' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => webhook.id,
          'url' => webhook.url
        )
      end

      it 'includes secret_key in detailed view' do
        get "/api/v1/webhooks/#{webhook.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('secret_key')
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
            event_types: [ 'user.created', 'user.updated' ]
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
    let(:webhook) { create(:webhook_endpoint, account: account, created_by: admin_user) }

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
            params: { webhook: { event_types: [ 'payment.completed' ] } },
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
    let(:webhook) { create(:webhook_endpoint, account: account, created_by: admin_user) }

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

  describe 'POST /api/v1/webhooks/:id/toggle_status' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:webhook) { create(:webhook_endpoint, account: account, status: 'active', created_by: admin_user) }

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

  describe 'GET /api/v1/webhooks/available_events' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }

    it 'returns available event types' do
      get '/api/v1/webhooks/available_events', headers: headers, as: :json

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

      get "/api/v1/webhooks/deliveries?webhook_id=#{webhook.id}",
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
        'timed_out_count'
      )
    end
  end

  # ==========================================================================
  # POST /api/v1/webhooks/retry_failed  (IMP-70b19d1bb6dc)
  #
  # Security regression guard for two defects on the unfixed action:
  #   1. Ungated: it was absent from every require_permission before_action, so
  #      ANY authenticated user (no webhook.update) could invoke it.
  #   2. Cross-tenant: the failed-delivery query (WebhookDelivery.failed) was NOT
  #      scoped to the caller's account, so one tenant could trigger a
  #      platform-wide retry storm across every other tenant's failed deliveries.
  #
  # WebhookRetryJob is defined only in the standalone worker app; the Rails
  # server never loads it. We stub it as a constant spy so we can both (a) keep
  # the unconditional perform_later call from raising NameError and (b) observe
  # exactly which deliveries get enqueued.
  # ==========================================================================
  describe 'POST /api/v1/webhooks/retry_failed' do
    let(:retry_job) { spy('WebhookRetryJob') }
    let(:caller_user) { create(:user, account: account, permissions: [ 'webhook.update' ]) }
    let(:caller_headers) { auth_headers_for(caller_user) }

    # Account A (the caller): one failed delivery that is retryable now
    # (next_retry_at in the past) on an active endpoint.
    let(:endpoint_a) { create(:webhook_endpoint, account: account, status: 'active') }
    let!(:delivery_a) do
      create(:webhook_delivery, :failed, webhook_endpoint: endpoint_a, next_retry_at: 1.minute.ago)
    end

    # Account B (a different tenant): likewise a retryable failed delivery on an
    # active endpoint. It must NEVER be enqueued when account A retries.
    let(:other_account) { create(:account) }
    let(:endpoint_b) { create(:webhook_endpoint, account: other_account, status: 'active') }
    let!(:delivery_b) do
      create(:webhook_delivery, :failed, webhook_endpoint: endpoint_b, next_retry_at: 1.minute.ago)
    end

    before { stub_const('WebhookRetryJob', retry_job) }

    it 'requires the webhook.update permission' do
      post '/api/v1/webhooks/retry_failed', headers: auth_headers_for(regular_user), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(retry_job).not_to have_received(:perform_later)
    end

    it 'only retries the calling account deliveries (no cross-tenant retry storm)' do
      post '/api/v1/webhooks/retry_failed', headers: caller_headers, as: :json

      expect_success_response
      expect(retry_job).to have_received(:perform_later).with(delivery_a.id)
      expect(retry_job).not_to have_received(:perform_later).with(delivery_b.id)

      expect(json_response['data']['retry_count']).to eq(1)
      expect(json_response['data']['total_failed']).to eq(1)
    end

    it 'queues the calling account retryable delivery (happy path)' do
      post '/api/v1/webhooks/retry_failed', headers: caller_headers, as: :json

      expect_success_response
      expect(json_response['data']['retry_count']).to eq(1)
      expect(retry_job).to have_received(:perform_later).with(delivery_a.id).once
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
    let(:webhook) { create(:webhook_endpoint, account: account, created_by: admin_user) }

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

  # ==========================================================================
  # REAL test paths (no test_endpoint stub)
  #
  # Regression guard: test_endpoint previously persisted each ping as a
  # webhook_delivery using non-existent columns, so health_test 500'd on every
  # real call; #test called a non-existent WebhookService and was dead. The fix
  # routes both through the SSRF-guarded WebhookHealthService#test_endpoint and
  # does NOT persist diagnostics as deliveries (which would skew health metrics).
  # ==========================================================================
  describe 'real test paths (no stub)' do
    let(:headers) { auth_headers_for(user_with_webhook_permission) }
    let(:endpoint) { create(:webhook_endpoint, account: account, created_by: admin_user) }

    before do
      # Public literal IP so the SSRF guard passes without DNS; stub the POST.
      endpoint.update_column(:url, 'http://93.184.216.34/webhook')
      stub_request(:post, 'http://93.184.216.34/webhook').to_return(status: 200, body: 'ok')
    end

    it 'POST /health_test succeeds end-to-end (no 500) without persisting a delivery' do
      expect do
        post "/api/v1/webhooks/#{endpoint.id}/health_test", headers: headers, as: :json
      end.not_to change(WebhookDelivery, :count)

      expect_success_response
      expect(json_response['data']['success']).to be true
      expect(json_response['data']['status_code']).to eq(200)
    end

    it 'POST /test succeeds end-to-end (no missing WebhookService) without persisting a delivery' do
      expect do
        post "/api/v1/webhooks/#{endpoint.id}/test", headers: headers, as: :json
      end.not_to change(WebhookDelivery, :count)

      expect_success_response
      data = json_response['data']
      expect(data['response']['success']).to be true
      expect(data['response']['status']).to eq(200)
    end

    it 'health_test reports failure (not 500) when the target is SSRF-blocked' do
      endpoint.update_column(:url, 'http://169.254.169.254/')
      stub_request(:post, 'http://169.254.169.254/').to_return(status: 200)

      post "/api/v1/webhooks/#{endpoint.id}/health_test", headers: headers, as: :json

      expect_success_response
      expect(json_response['data']['success']).to be false
    end
  end
end

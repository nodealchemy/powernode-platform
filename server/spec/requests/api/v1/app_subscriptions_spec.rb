# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppSubscriptions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['subscriptions.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app) }
  let(:app_plan) { create(:app_plan, app: app) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/app_subscriptions' do
    let!(:subscriptions) do
      [
        create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active'),
        create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'paused'),
        create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'cancelled')
      ]
    end

    context 'with authenticated user' do
      it 'returns all subscriptions for the account' do
        get '/api/v1/app_subscriptions', headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(3)
      end

      it 'filters by status' do
        get '/api/v1/app_subscriptions?status=active', headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('active')
      end

      it 'includes pagination metadata' do
        get '/api/v1/app_subscriptions', headers: headers, as: :json

        expect_success_response
        expect(json_response['pagination']).to include(
          'current_page',
          'total_pages',
          'total_count',
          'per_page'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/app_subscriptions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/app_subscriptions/active' do
    let!(:active_subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active') }
    let!(:inactive_subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'cancelled') }

    context 'with authenticated user' do
      it 'returns only active subscriptions' do
        get '/api/v1/app_subscriptions/active', headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('active')
      end
    end
  end

  describe 'GET /api/v1/app_subscriptions/cancelled' do
    let!(:cancelled_subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'cancelled') }

    context 'with authenticated user' do
      it 'returns only cancelled subscriptions' do
        get '/api/v1/app_subscriptions/cancelled', headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('cancelled')
      end
    end
  end

  describe 'GET /api/v1/app_subscriptions/:id' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }

    context 'with authenticated user' do
      it 'returns the subscription with detailed information' do
        get "/api/v1/app_subscriptions/#{subscription.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['id']).to eq(subscription.id)
        expect(data).to include(
          'status',
          'app',
          'app_plan',
          'configuration',
          'usage_metrics',
          'enabled_features'
        )
      end
    end

    context 'with subscription from another account' do
      let(:other_account) { create(:account) }
      let(:other_subscription) { create(:app_subscription, account: other_account, app: app, app_plan: app_plan) }

      it 'returns not found error' do
        get "/api/v1/app_subscriptions/#{other_subscription.id}", headers: headers, as: :json

        expect_error_response('Subscription not found', 404)
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions' do
    let(:valid_params) do
      {
        app_id: app.id,
        app_plan_id: app_plan.id,
        app_subscription: {
          configuration: { feature_flags: { advanced: true } }
        }
      }
    end

    context 'with authenticated user' do
      it 'creates a new subscription' do
        expect do
          post '/api/v1/app_subscriptions', params: valid_params, headers: headers, as: :json
        end.to change(account.app_subscriptions, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['status']).to eq('active')
        expect(json_response['message']).to eq('Successfully subscribed to app')
      end

      it 'prevents duplicate active subscriptions' do
        create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active')
        post '/api/v1/app_subscriptions', params: valid_params, headers: headers, as: :json

        expect_error_response('Already subscribed to this app', 409)
      end

      it 'returns error for non-existent app' do
        invalid_params = valid_params.merge(app_id: 'non-existent-id')
        post '/api/v1/app_subscriptions', params: invalid_params, headers: headers, as: :json

        expect_error_response('App not found', 404)
      end

      it 'returns error for non-existent plan' do
        invalid_params = valid_params.merge(app_plan_id: 'non-existent-id')
        post '/api/v1/app_subscriptions', params: invalid_params, headers: headers, as: :json

        expect_error_response('App plan not found', 404)
      end
    end
  end

  describe 'PUT /api/v1/app_subscriptions/:id' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }
    let(:update_params) do
      {
        app_subscription: {
          configuration: { updated: true }
        }
      }
    end

    context 'with authenticated user' do
      it 'updates the subscription' do
        put "/api/v1/app_subscriptions/#{subscription.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['configuration']['updated']).to be true
        expect(json_response['message']).to eq('Subscription updated successfully')
      end
    end
  end

  describe 'DELETE /api/v1/app_subscriptions/:id' do
    let!(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }

    context 'with authenticated user' do
      it 'deletes the subscription' do
        expect do
          delete "/api/v1/app_subscriptions/#{subscription.id}", headers: headers, as: :json
        end.to change(account.app_subscriptions, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('Subscription deleted successfully')
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions/:id/pause' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active') }

    context 'with authenticated user' do
      it 'pauses the subscription' do
        post "/api/v1/app_subscriptions/#{subscription.id}/pause", params: { reason: 'Taking a break' }, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['status']).to eq('paused')
        expect(json_response['message']).to eq('Subscription paused successfully')
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions/:id/resume' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'paused') }

    context 'with authenticated user' do
      it 'resumes the subscription' do
        post "/api/v1/app_subscriptions/#{subscription.id}/resume", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['status']).to eq('active')
        expect(json_response['message']).to eq('Subscription resumed successfully')
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions/:id/cancel' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active') }

    context 'with authenticated user' do
      it 'cancels the subscription' do
        post "/api/v1/app_subscriptions/#{subscription.id}/cancel", params: { reason: 'No longer needed' }, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['status']).to eq('cancelled')
        expect(json_response['message']).to eq('Subscription cancelled successfully')
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions/:id/upgrade_plan' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active') }
    let(:premium_plan) { create(:app_plan, app: app, price_cents: 10000) }

    context 'with authenticated user' do
      it 'upgrades to a new plan' do
        post "/api/v1/app_subscriptions/#{subscription.id}/upgrade_plan", params: { app_plan_id: premium_plan.id }, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['app_plan']['id']).to eq(premium_plan.id)
        expect(json_response['message']).to eq('Plan upgraded successfully')
      end

      it 'returns error for non-existent plan' do
        post "/api/v1/app_subscriptions/#{subscription.id}/upgrade_plan", params: { app_plan_id: 'non-existent-id' }, headers: headers, as: :json

        expect_error_response('App plan not found', 404)
      end
    end
  end

  describe 'POST /api/v1/app_subscriptions/:id/downgrade_plan' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan, status: 'active') }
    let(:basic_plan) { create(:app_plan, app: app, price_cents: 500) }

    context 'with authenticated user' do
      it 'downgrades to a new plan' do
        post "/api/v1/app_subscriptions/#{subscription.id}/downgrade_plan", params: { app_plan_id: basic_plan.id }, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['app_plan']['id']).to eq(basic_plan.id)
        expect(json_response['message']).to eq('Plan downgraded successfully')
      end
    end
  end

  describe 'GET /api/v1/app_subscriptions/:id/usage' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }

    context 'with authenticated user' do
      it 'returns usage data' do
        get "/api/v1/app_subscriptions/#{subscription.id}/usage", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'current_period_usage',
          'limits',
          'quota_usage',
          'remaining_quotas',
          'billing_info'
        )
      end
    end
  end

  describe 'GET /api/v1/app_subscriptions/:id/analytics' do
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }

    context 'with authenticated user' do
      it 'returns analytics data' do
        get "/api/v1/app_subscriptions/#{subscription.id}/analytics", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'subscription_age_days',
          'total_amount_paid',
          'average_monthly_usage',
          'usage_trends',
          'feature_usage'
        )
      end
    end
  end

  describe 'authorization' do
    let(:other_account) { create(:account) }
    let(:other_user) { create(:user, account: other_account, permissions: ['subscriptions.manage']) }
    let(:subscription) { create(:app_subscription, account: account, app: app, app_plan: app_plan) }

    it 'prevents accessing another account subscription' do
      get "/api/v1/app_subscriptions/#{subscription.id}", headers: auth_headers_for(other_user), as: :json

      expect_error_response('Subscription not found', 404)
    end

    it 'prevents modifying another account subscription' do
      post "/api/v1/app_subscriptions/#{subscription.id}/cancel", headers: auth_headers_for(other_user), as: :json

      expect_error_response('Subscription not found', 404)
    end
  end
end

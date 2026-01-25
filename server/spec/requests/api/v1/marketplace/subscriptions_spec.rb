# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Marketplace::Subscriptions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/marketplace/subscriptions' do
    context 'with authentication' do
      let!(:subscription1) { create(:marketplace_subscription, account: account, status: 'active') }
      let!(:subscription2) { create(:marketplace_subscription, account: account, status: 'paused') }

      it 'returns list of subscriptions for current account' do
        get '/api/v1/marketplace/subscriptions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to eq(2)
      end

      it 'filters by type' do
        get '/api/v1/marketplace/subscriptions',
            params: { type: 'workflow_template' },
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'filters by status' do
        get '/api/v1/marketplace/subscriptions',
            params: { status: 'active' },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data.all? { |s| s['status'] == 'active' }).to be true if data.any?
      end

      it 'paginates results' do
        get '/api/v1/marketplace/subscriptions',
            params: { page: 1, per_page: 10 },
            headers: headers,
            as: :json

        expect_success_response
        meta = json_response['meta']
        expect(meta['current_page']).to eq(1)
        expect(meta['per_page']).to eq(10)
      end

      it 'includes count metadata' do
        get '/api/v1/marketplace/subscriptions', headers: headers, as: :json

        expect_success_response
        meta = json_response['meta']
        expect(meta).to have_key('counts_by_type')
        expect(meta).to have_key('counts_by_status')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/marketplace/subscriptions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/marketplace/subscriptions/:id' do
    let(:subscription) { create(:marketplace_subscription, account: account) }

    context 'with authentication and authorization' do
      it 'returns subscription details' do
        get "/api/v1/marketplace/subscriptions/#{subscription.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(subscription.id)
        expect(data).to have_key('usage_metrics')
        expect(data).to have_key('configuration')
        expect(data).to have_key('item')
      end
    end

    context 'accessing subscription from different account' do
      let(:other_account) { create(:account) }
      let(:other_subscription) { create(:marketplace_subscription, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/marketplace/subscriptions/#{other_subscription.id}", headers: headers, as: :json

        expect_error_response('Subscription not found', 404)
      end
    end
  end

  describe 'POST /api/v1/marketplace/subscriptions' do
    let(:workflow_template) { create(:ai_workflow_template, :published) }
    let(:valid_params) do
      {
        item_type: 'workflow_template',
        item_id: workflow_template.id,
        tier: 'standard'
      }
    end

    context 'with authentication' do
      it 'creates a new subscription' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscribe)
          .and_return({
            success: true,
            data: create(:marketplace_subscription, account: account)
          })

        post '/api/v1/marketplace/subscriptions', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data).to have_key('id')
        expect(data).to have_key('item_id')
        expect(data).to have_key('status')
      end

      it 'returns error when subscription fails' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscribe)
          .and_return({
            success: false,
            errors: ['Subscription failed']
          })

        post '/api/v1/marketplace/subscriptions', params: valid_params, headers: headers, as: :json

        expect_error_response('Subscription failed', 422)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/marketplace/subscriptions', params: valid_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/marketplace/subscriptions/:id' do
    let(:subscription) { create(:marketplace_subscription, account: account) }
    let(:update_params) do
      {
        configuration: {
          setting1: 'value1',
          setting2: 'value2'
        }
      }
    end

    context 'with proper authorization' do
      it 'updates subscription configuration' do
        patch "/api/v1/marketplace/subscriptions/#{subscription.id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['configuration']).to include('setting1' => 'value1')
      end
    end
  end

  describe 'DELETE /api/v1/marketplace/subscriptions/:id' do
    let!(:subscription) { create(:marketplace_subscription, account: account) }

    context 'with proper authorization' do
      it 'cancels the subscription' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:unsubscribe)
          .and_return({ success: true })

        delete "/api/v1/marketplace/subscriptions/#{subscription.id}",
               params: { reason: 'No longer needed' },
               headers: headers,
               as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Subscription cancelled successfully')
      end

      it 'returns error when cancellation fails' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:unsubscribe)
          .and_return({ success: false, errors: ['Cancellation failed'] })

        delete "/api/v1/marketplace/subscriptions/#{subscription.id}", headers: headers, as: :json

        expect_error_response('Cancellation failed', 422)
      end
    end
  end

  describe 'POST /api/v1/marketplace/subscriptions/:id/pause' do
    let(:subscription) { create(:marketplace_subscription, account: account, status: 'active') }

    context 'with proper authorization' do
      it 'pauses the subscription' do
        post "/api/v1/marketplace/subscriptions/#{subscription.id}/pause",
             params: { reason: 'Temporary pause' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('paused')
      end
    end
  end

  describe 'POST /api/v1/marketplace/subscriptions/:id/resume' do
    let(:subscription) { create(:marketplace_subscription, account: account, status: 'paused') }

    context 'with proper authorization' do
      it 'resumes the subscription' do
        post "/api/v1/marketplace/subscriptions/#{subscription.id}/resume", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('active')
      end
    end
  end

  describe 'PATCH /api/v1/marketplace/subscriptions/:id/configure' do
    let(:subscription) { create(:marketplace_subscription, account: account) }
    let(:config_params) do
      {
        configuration: {
          max_usage: 100,
          notifications: true
        }
      }
    end

    context 'with proper authorization' do
      it 'updates subscription configuration' do
        patch "/api/v1/marketplace/subscriptions/#{subscription.id}/configure",
              params: config_params,
              headers: headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['configuration']).to include('max_usage' => 100)
      end
    end
  end

  describe 'POST /api/v1/marketplace/subscriptions/:id/upgrade_tier' do
    let(:subscription) { create(:marketplace_subscription, account: account, tier: 'basic') }

    context 'with proper authorization' do
      it 'upgrades subscription tier' do
        post "/api/v1/marketplace/subscriptions/#{subscription.id}/upgrade_tier",
             params: { tier: 'premium' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['tier']).to eq('premium')
      end
    end
  end

  describe 'GET /api/v1/marketplace/subscriptions/:id/usage' do
    let(:subscription) { create(:marketplace_subscription, account: account) }

    context 'with proper authorization' do
      it 'returns usage metrics' do
        get "/api/v1/marketplace/subscriptions/#{subscription.id}/usage", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['subscription_id']).to eq(subscription.id)
        expect(data).to have_key('usage_metrics')
        expect(data).to have_key('usage_within_limits')
        expect(data).to have_key('subscription_age_days')
      end
    end
  end
end

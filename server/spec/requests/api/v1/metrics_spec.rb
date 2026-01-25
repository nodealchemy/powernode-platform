# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Metrics', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }

  before do
    # Set start time for uptime calculation
    Rails.application.config.start_time = 1.hour.ago
  end

  describe 'GET /api/v1/metrics/health' do
    it 'returns health check without authentication' do
      get '/api/v1/metrics/health', as: :json

      expect_success_response
      data = json_response_data
      expect(data['status']).to eq('healthy')
      expect(data['timestamp']).to be_present
      expect(data['uptime']).to be > 0
      expect(data).to have_key('database')
      expect(data).to have_key('redis')
      expect(data).to have_key('memory')
      expect(data).to have_key('business_metrics')
    end

    it 'includes database health check' do
      get '/api/v1/metrics/health', as: :json

      expect_success_response
      data = json_response_data
      expect(data['database']['status']).to eq('healthy')
      expect(data['database']).to have_key('response_time_ms')
    end

    it 'includes redis health check' do
      get '/api/v1/metrics/health', as: :json

      expect_success_response
      data = json_response_data
      expect(data['redis']['status']).to eq('healthy')
      expect(data['redis']).to have_key('response_time_ms')
    end

    it 'includes business metrics' do
      create_list(:user, 3, account: account)

      get '/api/v1/metrics/health', as: :json

      expect_success_response
      data = json_response_data
      expect(data['business_metrics']).to have_key('total_users')
      expect(data['business_metrics']).to have_key('active_subscriptions')
    end

    it 'handles database errors gracefully' do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError)

      get '/api/v1/metrics/health', as: :json

      expect_error_response('Health check failed', 503)
    end
  end

  describe 'GET /api/v1/metrics/prometheus' do
    it 'returns service unavailable' do
      get '/api/v1/metrics/prometheus', as: :json

      expect_error_response('Prometheus metrics disabled in development', 503)
    end
  end

  describe 'GET /api/v1/metrics/application' do
    context 'with analytics.read permission' do
      before do
        user.roles.first.permissions.create!(name: 'analytics.read')
      end

      it 'returns detailed application metrics' do
        get '/api/v1/metrics/application', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('users')
        expect(data).to have_key('subscriptions')
        expect(data).to have_key('payments')
        expect(data).to have_key('api')
        expect(data).to have_key('background_jobs')
        expect(data).to have_key('system')
      end

      it 'includes user metrics' do
        create_list(:user, 5, account: account)

        get '/api/v1/metrics/application', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['users']['total']).to be > 0
        expect(data['users']).to have_key('active')
        expect(data['users']).to have_key('created_today')
        expect(data['users']).to have_key('by_role')
      end

      it 'includes subscription metrics' do
        plan = create(:plan, account: account)
        create_list(:subscription, 3, account: account, plan: plan, status: 'active')

        get '/api/v1/metrics/application', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['subscriptions']['total']).to be > 0
        expect(data['subscriptions']).to have_key('active')
        expect(data['subscriptions']).to have_key('by_plan')
        expect(data['subscriptions']).to have_key('monthly_revenue_cents')
      end

      it 'includes payment metrics' do
        invoice = create(:invoice, account: account)
        create(:payment, :succeeded, account: account, invoice: invoice)
        create(:payment, :failed, account: account, invoice: invoice)

        get '/api/v1/metrics/application', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['payments']['total']).to be > 0
        expect(data['payments']).to have_key('successful')
        expect(data['payments']).to have_key('failed')
        expect(data['payments']).to have_key('total_amount_cents')
      end

      it 'includes system metrics' do
        get '/api/v1/metrics/application', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['system']['rails_version']).to eq(Rails.version)
        expect(data['system']['ruby_version']).to eq(RUBY_VERSION)
        expect(data['system']['environment']).to eq(Rails.env)
        expect(data['system']).to have_key('database_size')
      end
    end

    context 'without analytics.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/metrics/application', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/metrics/application', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end

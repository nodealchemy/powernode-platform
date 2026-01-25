# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Analytics', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:plan) { create(:plan) }

  let(:analytics_reader) do
    create(:user, account: account, permissions: ['ai.analytics.read'])
  end

  let(:analytics_exporter) do
    create(:user, account: account, permissions: ['ai.analytics.read', 'ai.analytics.export'])
  end

  let(:admin_user) do
    create(:user, account: account, permissions: ['admin.access'])
  end

  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/analytics/live' do
    context 'with ai.analytics.read permission' do
      it 'returns live analytics data' do
        get '/api/v1/analytics/live', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'current_metrics',
          'today_activity',
          'weekly_trend',
          'last_updated'
        )
      end

      it 'includes current metrics' do
        get '/api/v1/analytics/live', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        metrics = json_response['data']['current_metrics']

        expect(metrics).to include(
          'mrr',
          'arr',
          'active_customers',
          'churn_rate',
          'arpu',
          'growth_rate'
        )
      end

      it 'includes today activity metrics' do
        get '/api/v1/analytics/live', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        today = json_response['data']['today_activity']

        expect(today).to include(
          'new_subscriptions',
          'cancelled_subscriptions',
          'payments_processed',
          'failed_payments',
          'revenue_today'
        )
      end

      it 'respects force_refresh parameter' do
        get '/api/v1/analytics/live?force_refresh=true',
            headers: auth_headers_for(analytics_reader),
            as: :json

        expect_success_response
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/live', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/revenue' do
    context 'with permission' do
      it 'returns revenue analytics' do
        get '/api/v1/analytics/revenue', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'current_metrics',
          'historical_data',
          'period'
        )
      end

      it 'includes current metrics' do
        get '/api/v1/analytics/revenue', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        metrics = json_response['data']['current_metrics']

        expect(metrics).to include(
          'mrr',
          'arr',
          'active_subscriptions',
          'total_customers',
          'arpu',
          'growth_rate'
        )
      end

      it 'respects date range parameters' do
        start_date = 3.months.ago.to_date.iso8601
        end_date = Date.current.iso8601

        get "/api/v1/analytics/revenue?start_date=#{start_date}&end_date=#{end_date}",
            headers: auth_headers_for(analytics_reader),
            as: :json

        expect_success_response
        period = json_response['data']['period']

        expect(period['start_date']).to eq(start_date)
        expect(period['end_date']).to eq(end_date)
      end

      it 'validates date range' do
        start_date = Date.current.iso8601
        end_date = 1.month.ago.to_date.iso8601

        get "/api/v1/analytics/revenue?start_date=#{start_date}&end_date=#{end_date}",
            headers: auth_headers_for(analytics_reader),
            as: :json

        expect_error_response('Start date must be before end date', 400)
      end

      it 'limits maximum date range' do
        start_date = 3.years.ago.to_date.iso8601
        end_date = Date.current.iso8601

        get "/api/v1/analytics/revenue?start_date=#{start_date}&end_date=#{end_date}",
            headers: auth_headers_for(analytics_reader),
            as: :json

        expect_error_response('Date range too large (max 2 years)', 400)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/revenue', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/growth' do
    context 'with permission' do
      it 'returns growth analytics' do
        get '/api/v1/analytics/growth', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'compound_monthly_growth_rate',
          'monthly_growth_data',
          'forecasting',
          'period'
        )
      end

      it 'includes monthly growth data' do
        get '/api/v1/analytics/growth', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']['monthly_growth_data']).to be_an(Array)
      end

      it 'includes forecasting data' do
        get '/api/v1/analytics/growth', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        forecasting = json_response['data']['forecasting']

        expect(forecasting).to include('next_month_projection', 'confidence_interval')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/growth', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/churn' do
    context 'with permission' do
      it 'returns churn analytics' do
        get '/api/v1/analytics/churn', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'current_metrics',
          'churn_trend',
          'insights',
          'period'
        )
      end

      it 'includes current churn metrics' do
        get '/api/v1/analytics/churn', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        metrics = json_response['data']['current_metrics']

        expect(metrics).to include(
          'customer_churn_rate',
          'average_customer_churn_rate',
          'average_revenue_churn_rate',
          'customer_retention_rate'
        )
      end

      it 'includes churn insights' do
        get '/api/v1/analytics/churn', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        insights = json_response['data']['insights']

        expect(insights).to include('churn_risk_level', 'recommended_actions')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/churn', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/cohorts' do
    context 'with permission' do
      it 'returns cohort analytics' do
        get '/api/v1/analytics/cohorts', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include('cohorts', 'summary')
      end

      it 'includes cohort summary' do
        get '/api/v1/analytics/cohorts', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        summary = json_response['data']['summary']

        expect(summary).to include(
          'total_cohorts',
          'average_first_month_retention',
          'average_six_month_retention'
        )
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/cohorts', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/customers' do
    context 'with permission' do
      it 'returns customer analytics' do
        get '/api/v1/analytics/customers', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'current_metrics',
          'customer_growth_trend',
          'segmentation',
          'period'
        )
      end

      it 'includes current customer metrics' do
        get '/api/v1/analytics/customers', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        metrics = json_response['data']['current_metrics']

        expect(metrics).to include(
          'total_customers',
          'arpu',
          'ltv',
          'ltv_to_cac_ratio'
        )
      end

      it 'includes customer segmentation' do
        get '/api/v1/analytics/customers', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
        segmentation = json_response['data']['segmentation']

        expect(segmentation).to include('by_plan', 'by_tenure')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/customers', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Analytics permission required', 403)
      end
    end
  end

  describe 'GET /api/v1/analytics/export' do
    context 'with export permission' do
      it 'exports as CSV by default' do
        get '/api/v1/analytics/export', headers: auth_headers_for(analytics_exporter), as: :json

        expect_success_response
        expect(json_response['data']).to include('csv_data', 'filename')
      end

      it 'respects format parameter' do
        get '/api/v1/analytics/export?format=csv',
            headers: auth_headers_for(analytics_exporter),
            as: :json

        expect_success_response
      end

      it 'respects report_type parameter' do
        get '/api/v1/analytics/export?report_type=revenue',
            headers: auth_headers_for(analytics_exporter),
            as: :json

        expect_success_response
        expect(json_response['data']['filename']).to include('revenue')
      end
    end

    context 'without export permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/export', headers: auth_headers_for(analytics_reader), as: :json

        expect_error_response('Export permission required', 403)
      end
    end

    context 'without any analytics permission' do
      it 'returns forbidden error' do
        get '/api/v1/analytics/export', headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Export permission required', 403)
      end
    end
  end

  describe 'account scoping' do
    let(:other_account) { create(:account) }

    context 'with admin.access permission' do
      it 'allows global analytics without account_id' do
        get '/api/v1/analytics/revenue', headers: auth_headers_for(admin_user), as: :json

        expect_success_response
      end

      it 'allows querying specific account' do
        get "/api/v1/analytics/revenue?account_id=#{other_account.id}",
            headers: auth_headers_for(admin_user),
            as: :json

        expect_success_response
      end
    end

    context 'without admin.access permission' do
      it 'scopes to user account only' do
        get '/api/v1/analytics/revenue', headers: auth_headers_for(analytics_reader), as: :json

        expect_success_response
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Roi', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.roi.read', 'ai.roi.manage' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.roi.read' ]) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }

  let(:roi_service) { instance_double(Ai::RoiAnalyticsService) }

  before do
    allow(Ai::RoiAnalyticsService).to receive(:new).and_return(roi_service)
  end

  describe 'GET /api/v1/ai/roi/dashboard' do
    context 'with proper permissions' do
      it 'returns dashboard data' do
        dashboard_data = { total_cost: 100, total_savings: 200, roi: 2.0 }
        allow(roi_service).to receive(:dashboard).and_return(dashboard_data)

        get '/api/v1/ai/roi/dashboard', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['dashboard']).to eq(dashboard_data.deep_stringify_keys)
        expect(data['time_range']).to be_present
      end

      it 'accepts hourly_rate parameter' do
        allow(roi_service).to receive(:dashboard).and_return({})

        get '/api/v1/ai/roi/dashboard?hourly_rate=100', headers: headers, as: :json

        expect_success_response
        expect(Ai::RoiAnalyticsService).to have_received(:new)
          .with(account: account, hourly_rate: 100.0)
      end

      it 'accepts time_range parameter' do
        allow(roi_service).to receive(:dashboard).and_return({})

        get '/api/v1/ai/roi/dashboard?time_range=7d', headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:dashboard).with(period: 7.days)
      end
    end

    context 'without ai.roi.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get '/api/v1/ai/roi/dashboard', headers: headers_without_permission, as: :json

        expect_error_response('Permission denied: ai.roi.read', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/roi/summary' do
    context 'with proper permissions' do
      it 'returns summary metrics' do
        summary = { total_executions: 100, total_cost: 50 }
        allow(roi_service).to receive(:summary_metrics).and_return(summary)

        get '/api/v1/ai/roi/summary', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['summary']).to eq(summary.deep_stringify_keys)
      end

      it 'accepts period parameter' do
        allow(roi_service).to receive(:summary_metrics).and_return({})

        get '/api/v1/ai/roi/summary?period=14', headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:summary_metrics).with(14.days)
      end
    end
  end

  describe 'GET /api/v1/ai/roi/trends' do
    context 'with proper permissions' do
      it 'returns trend data' do
        trends = [ { date: '2024-01-01', roi: 1.5 } ]
        allow(roi_service).to receive(:roi_trends).and_return(trends)

        get '/api/v1/ai/roi/trends', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['trends']).to eq(trends.map(&:deep_stringify_keys))
      end
    end
  end

  describe 'GET /api/v1/ai/roi/daily_metrics' do
    context 'with proper permissions' do
      it 'returns daily metrics' do
        metrics = [ { date: '2024-01-01', cost: 10 } ]
        allow(roi_service).to receive(:daily_metrics).and_return(metrics)

        get '/api/v1/ai/roi/daily_metrics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['metrics']).to eq(metrics.map(&:deep_stringify_keys))
        expect(data['days']).to eq(30)
      end

      it 'accepts custom days parameter' do
        allow(roi_service).to receive(:daily_metrics).and_return([])

        get '/api/v1/ai/roi/daily_metrics?days=7', headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:daily_metrics).with(days: 7)
      end
    end
  end

  describe 'GET /api/v1/ai/roi/by_workflow' do
    context 'with proper permissions' do
      it 'returns ROI by workflow' do
        workflow_data = [ { workflow_id: 'w1', roi: 2.0 } ]
        allow(roi_service).to receive(:roi_by_workflow).and_return(workflow_data)

        get '/api/v1/ai/roi/by_workflow', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['workflows']).to eq(workflow_data.map(&:deep_stringify_keys))
      end
    end
  end

  describe 'GET /api/v1/ai/roi/by_agent' do
    context 'with proper permissions' do
      it 'returns ROI by agent' do
        agent_data = [ { agent_id: 'a1', roi: 1.8 } ]
        allow(roi_service).to receive(:roi_by_agent).and_return(agent_data)

        get '/api/v1/ai/roi/by_agent', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['agents']).to eq(agent_data.map(&:deep_stringify_keys))
      end
    end
  end

  describe 'GET /api/v1/ai/roi/by_provider' do
    context 'with proper permissions' do
      it 'returns cost by provider' do
        provider_data = [ { provider: 'openai', cost: 50 } ]
        allow(roi_service).to receive(:cost_by_provider).and_return(provider_data)

        get '/api/v1/ai/roi/by_provider', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['providers']).to eq(provider_data.map(&:deep_stringify_keys))
      end
    end
  end

  describe 'GET /api/v1/ai/roi/cost_breakdown' do
    context 'with proper permissions' do
      it 'returns detailed cost breakdown' do
        allow(Ai::CostAttribution).to receive(:cost_breakdown_by_category).and_return([])
        allow(Ai::CostAttribution).to receive(:cost_breakdown_by_source_type).and_return([])
        allow(Ai::CostAttribution).to receive(:cost_breakdown_by_provider).and_return([])
        allow(Ai::CostAttribution).to receive(:daily_cost_trend).and_return([])
        allow(Ai::CostAttribution).to receive(:top_cost_sources).and_return([])

        get '/api/v1/ai/roi/cost_breakdown', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['cost_breakdown']).to include(
          'by_category',
          'by_source_type',
          'by_provider',
          'daily_trend',
          'top_sources'
        )
      end
    end
  end

  describe 'GET /api/v1/ai/roi/attributions' do
    let!(:attribution) { create(:ai_cost_attribution, account: account) }

    context 'with proper permissions' do
      it 'returns cost attributions' do
        get '/api/v1/ai/roi/attributions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['attributions']).to be_an(Array)
      end

      it 'filters by date' do
        get "/api/v1/ai/roi/attributions?date=#{Date.current}", headers: headers, as: :json

        expect_success_response
      end

      it 'filters by category' do
        get '/api/v1/ai/roi/attributions?category=workflow', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/roi/metrics' do
    let!(:metric) { create(:ai_roi_metric, account: account) }

    context 'with proper permissions' do
      it 'returns ROI metrics' do
        get '/api/v1/ai/roi/metrics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['metrics']).to be_an(Array)
      end

      it 'filters by metric_type' do
        get '/api/v1/ai/roi/metrics?metric_type=daily', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/roi/metrics/:id' do
    let(:metric) { create(:ai_roi_metric, account: account) }

    context 'with proper permissions' do
      it 'returns metric details' do
        get "/api/v1/ai/roi/metrics/#{metric.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['metric']).to be_present
      end

      it 'returns not found for non-existent metric' do
        get "/api/v1/ai/roi/metrics/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Metric not found', 404)
      end
    end
  end

  describe 'GET /api/v1/ai/roi/projections' do
    context 'with proper permissions' do
      it 'returns projection data' do
        projections = { projected_cost: 100, projected_savings: 200 }
        allow(roi_service).to receive(:projections).and_return(projections)

        get '/api/v1/ai/roi/projections', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['projections']).to eq(projections.deep_stringify_keys)
      end

      it 'handles insufficient data gracefully' do
        allow(roi_service).to receive(:projections).and_return(nil)

        get '/api/v1/ai/roi/projections', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['projections']).to be_nil
        expect(data['message']).to include('Insufficient data')
      end
    end
  end

  describe 'GET /api/v1/ai/roi/recommendations' do
    context 'with proper permissions' do
      it 'returns recommendations' do
        recommendations = [ { type: 'cost_reduction', suggestion: 'Use smaller model' } ]
        allow(roi_service).to receive(:recommendations).and_return(recommendations)

        get '/api/v1/ai/roi/recommendations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['recommendations']).to eq(recommendations.map(&:deep_stringify_keys))
      end
    end
  end

  describe 'GET /api/v1/ai/roi/compare' do
    context 'with proper permissions' do
      it 'returns period comparison' do
        comparison = { current: {}, previous: {}, change: {} }
        allow(roi_service).to receive(:compare_periods).and_return(comparison)

        get '/api/v1/ai/roi/compare', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comparison']).to eq(comparison.deep_stringify_keys)
      end

      it 'accepts custom periods' do
        allow(roi_service).to receive(:compare_periods).and_return({})

        get '/api/v1/ai/roi/compare?current_period=7&previous_period=14', headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:compare_periods)
          .with(current_period: 7.days, previous_period: 14.days)
      end
    end
  end

  describe 'POST /api/v1/ai/roi/calculate' do
    context 'with proper permissions' do
      it 'calculates ROI for today by default' do
        metric = double(summary: { roi: 1.5 })
        allow(roi_service).to receive(:calculate_for_date).and_return(metric)

        post '/api/v1/ai/roi/calculate', headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:calculate_for_date).with(date: Date.current)
      end

      it 'calculates ROI for specific date' do
        metric = double(summary: { roi: 1.5 })
        allow(roi_service).to receive(:calculate_for_date).and_return(metric)

        post '/api/v1/ai/roi/calculate',
             params: { date: '2024-01-01' }, headers: headers, as: :json

        expect_success_response
      end

      it 'calculates ROI for date range' do
        allow(roi_service).to receive(:calculate_for_range).and_return([])

        post '/api/v1/ai/roi/calculate',
             params: { start_date: '2024-01-01', end_date: '2024-01-31' },
             headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without ai.roi.manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/roi/calculate', headers: read_only_headers, as: :json

        expect_error_response('Permission denied: ai.roi.manage', 403)
      end
    end
  end

  describe 'POST /api/v1/ai/roi/aggregate' do
    context 'with proper permissions' do
      it 'aggregates metrics' do
        result = { period_type: 'weekly', metrics: {} }
        allow(roi_service).to receive(:aggregate_metrics).and_return(result)

        post '/api/v1/ai/roi/aggregate', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['aggregation']).to eq(result.deep_stringify_keys)
      end

      it 'accepts custom period type' do
        allow(roi_service).to receive(:aggregate_metrics).and_return({})

        post '/api/v1/ai/roi/aggregate',
             params: { period_type: 'monthly' }, headers: headers, as: :json

        expect_success_response
        expect(roi_service).to have_received(:aggregate_metrics)
          .with(hash_including(period_type: 'monthly'))
      end
    end

    context 'without ai.roi.manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/roi/aggregate', headers: read_only_headers, as: :json

        expect_error_response('Permission denied: ai.roi.manage', 403)
      end
    end
  end
end

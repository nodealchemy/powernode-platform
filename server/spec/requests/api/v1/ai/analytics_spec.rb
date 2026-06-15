# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Analytics', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.analytics.read', 'ai.analytics.create', 'ai.analytics.export' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.analytics.read' ]) }
  let(:manage_user) { create(:user, account: account, permissions: [ 'ai.analytics.read', 'ai.analytics.create', 'ai.analytics.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  let(:dashboard_service) { instance_double('Ai::Analytics::DashboardService') }
  let(:metrics_service) { instance_double('Ai::Analytics::MetricsService') }
  let(:cost_service) { instance_double('Ai::Analytics::CostAnalysisService') }
  let(:performance_service) { instance_double('Ai::Analytics::PerformanceAnalysisService') }
  let(:report_service) { instance_double('Ai::Analytics::ReportService') }

  before do
    allow(Ai::Analytics::DashboardService).to receive(:new).and_return(dashboard_service)
    allow(Ai::Analytics::MetricsService).to receive(:new).and_return(metrics_service)
    allow(Ai::Analytics::CostAnalysisService).to receive(:new).and_return(cost_service)
    allow(Ai::Analytics::PerformanceAnalysisService).to receive(:new).and_return(performance_service)
    allow(Ai::Analytics::ReportService).to receive(:new).and_return(report_service)
  end

  describe 'GET /api/v1/ai/analytics/dashboard' do
    let(:dashboard_data) do
      {
        total_executions: 1000,
        success_rate: 98.5,
        total_cost: 100.0
      }
    end

    before do
      allow(dashboard_service).to receive(:generate).and_return(dashboard_data)
    end

    context 'with ai.analytics.read permission' do
      it 'returns dashboard analytics' do
        get '/api/v1/ai/analytics/dashboard',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('dashboard')
        expect(data).to have_key('time_range')
        expect(data).to have_key('generated_at')
      end

      it 'accepts time_range parameter' do
        get '/api/v1/ai/analytics/dashboard?time_range=7d',
            headers: headers,
            as: :json

        expect_success_response
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/ai/analytics/dashboard',
            headers: auth_headers_for(regular_user),
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/overview' do
    before do
      allow(dashboard_service).to receive(:generate_summary_metrics).and_return({})
      allow(dashboard_service).to receive(:generate_trend_data).and_return([])
      allow(dashboard_service).to receive(:generate_highlights).and_return([])
      allow(dashboard_service).to receive(:generate_quick_stats).and_return({})
    end

    context 'with permission' do
      it 'returns overview data' do
        get '/api/v1/ai/analytics/overview',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('overview')
        expect(data['overview']).to have_key('summary')
        expect(data['overview']).to have_key('trends')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/metrics' do
    let(:metrics_data) do
      {
        execution_count: 500,
        avg_latency: 150.0,
        error_rate: 1.5
      }
    end

    before do
      allow(metrics_service).to receive(:all_metrics).and_return(metrics_data)
    end

    context 'with permission' do
      it 'returns all metrics' do
        get '/api/v1/ai/analytics/metrics',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('metrics')
        expect(data).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/real_time' do
    let(:real_time_data) do
      {
        current_requests: 10,
        active_agents: 5
      }
    end

    before do
      allow(dashboard_service).to receive(:real_time_metrics).and_return(real_time_data)
    end

    context 'with permission' do
      it 'returns real-time metrics' do
        get '/api/v1/ai/analytics/real_time',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('metrics')
        expect(data).to have_key('refresh_interval')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/cost_analysis' do
    let(:cost_data) do
      {
        total_cost: 500.0,
        cost_by_provider: {},
        cost_trend: []
      }
    end

    before do
      allow(cost_service).to receive(:full_analysis).and_return(cost_data)
    end

    context 'with permission' do
      it 'returns cost analysis' do
        get '/api/v1/ai/analytics/cost_analysis',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('cost_analysis')
        expect(data).to have_key('time_range')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/performance_analysis' do
    let(:performance_data) do
      {
        avg_latency: 100.0,
        p95_latency: 200.0,
        bottlenecks: []
      }
    end

    before do
      allow(performance_service).to receive(:full_analysis).and_return(performance_data)
    end

    context 'with permission' do
      it 'returns performance analysis' do
        get '/api/v1/ai/analytics/performance_analysis',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('performance_analysis')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/insights' do
    let(:insights_data) do
      [
        { type: 'cost_saving', message: 'Switch to cheaper model' }
      ]
    end

    before do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with(/ai:analytics:insights/, any_args).and_return(insights_data)
    end

    context 'with permission' do
      it 'returns analytics insights' do
        get '/api/v1/ai/analytics/insights',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('insights')
        expect(data).to have_key('generated_at')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/recommendations' do
    before do
      allow(cost_service).to receive(:estimate_cost_savings).and_return({ opportunities: [] })
      allow(performance_service).to receive(:identify_bottlenecks).and_return([])
      allow(performance_service).to receive(:analyze_error_rates).and_return({ error_rate: 2.0 })
    end

    context 'with permission' do
      it 'returns optimization recommendations' do
        get '/api/v1/ai/analytics/recommendations',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('recommendations')
        expect(data).to have_key('generated_at')
      end
    end
  end

  # Previously-missing actions: routes declared performance/costs/usage/trends/
  # formats but the controller never implemented them (ActionNotFound -> 500).
  # Each now returns its frontend interface shape from the existing services.
  describe 'GET /api/v1/ai/analytics/costs' do
    before do
      allow(cost_service).to receive(:calculate_total_cost).and_return({ total: 12.5 })
      allow(cost_service).to receive(:cost_breakdown_by_provider).and_return([{ provider_name: 'openai', total_cost: 10.0, total_tokens: 1000 }])
      allow(cost_service).to receive(:cost_breakdown_by_agent).and_return([{ agent_name: 'A1', total_cost: 5.0 }])
      allow(cost_service).to receive(:daily_cost_breakdown).and_return({ '2026-06-01' => 5.0 })
      allow(cost_service).to receive(:estimate_cost_savings).and_return({ total_potential_savings: 2.0, opportunities: [] })
    end

    it 'returns CostAnalytics-shaped data' do
      get '/api/v1/ai/analytics/costs', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('total_cost_usd', 'cost_by_provider', 'cost_by_component', 'cost_trend', 'optimization_potential_usd')
      expect(data['total_cost_usd']).to eq(12.5)
      expect(data['cost_by_provider']).to eq({ 'openai' => 10.0 })
      expect(data['cost_trend']).to eq([{ 'date' => '2026-06-01', 'cost_usd' => 5.0 }])
    end
  end

  describe 'GET /api/v1/ai/analytics/performance' do
    before do
      allow(performance_service).to receive(:analyze_response_times).and_return({ avg_ms: 100.0, median_ms: 90.0, p95_ms: 200.0, p99_ms: 300.0 })
      allow(performance_service).to receive(:analyze_throughput).and_return({ executions_per_hour: 5.0 })
      allow(performance_service).to receive(:analyze_error_rates).and_return({ error_rate: 1.5 })
    end

    it 'returns PerformanceMetrics-shaped data' do
      get '/api/v1/ai/analytics/performance', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('avg_execution_time_ms', 'p50_execution_time_ms', 'p95_execution_time_ms', 'p99_execution_time_ms', 'throughput_per_hour', 'error_rate', 'by_component')
      expect(data['p50_execution_time_ms']).to eq(90.0)
      expect(data['error_rate']).to eq(1.5)
    end
  end

  describe 'GET /api/v1/ai/analytics/usage' do
    before do
      allow(dashboard_service).to receive(:generate_trend_data).and_return({ executions_by_day: { '2026-06-01' => 3 } })
      allow(cost_service).to receive(:cost_breakdown_by_provider).and_return([{ provider_name: 'openai', total_tokens: 1000 }])
      allow(metrics_service).to receive(:agent_metrics).and_return({ agents_by_type: { 'assistant' => 2 } })
    end

    it 'returns UsageMetrics-shaped data' do
      get '/api/v1/ai/analytics/usage', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('total_executions', 'executions_by_day', 'executions_by_type', 'active_users', 'total_tokens_used', 'tokens_by_provider')
      expect(data['total_executions']).to eq(3)
      expect(data['total_tokens_used']).to eq(1000)
      expect(data['tokens_by_provider']).to eq({ 'openai' => 1000 })
    end
  end

  describe 'GET /api/v1/ai/analytics/trends' do
    before do
      allow(dashboard_service).to receive(:generate_trend_data).and_return({
        executions_by_day: { '2026-06-01' => 2, '2026-06-02' => 4 },
        cost_by_day: { '2026-06-01' => 1.0, '2026-06-02' => 2.0 }
      })
    end

    it 'returns an array of Trend objects' do
      get '/api/v1/ai/analytics/trends', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.map { |t| t['metric'] }).to include('executions', 'cost_usd')
      exec_trend = data.find { |t| t['metric'] == 'executions' }
      expect(exec_trend).to include('direction', 'change_percentage', 'data_points')
      expect(exec_trend['direction']).to eq('up')
    end
  end

  describe 'GET /api/v1/ai/analytics/formats' do
    it 'returns the export-format catalog' do
      get '/api/v1/ai/analytics/formats', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.map { |f| f['format'] }).to include('json', 'csv', 'xlsx')
    end
  end

  # Regression: insights & recommendations must work against the REAL analytics
  # services, not instance_doubles. The file-wide `before` stubs every service,
  # and the per-endpoint specs further stubbed identify_bottlenecks to a Hash
  # ({ bottlenecks: [] }). The real service returns an Array, so the controller's
  # `bottlenecks[:bottlenecks]` raised TypeError in production (500) while every
  # stubbed spec stayed green. These examples undo the doubling for the
  # aggregation services so the real contract is exercised.
  describe 'aggregation against real analytics services (no service doubles)' do
    before do
      allow(Ai::Analytics::CostAnalysisService).to receive(:new).and_call_original
      allow(Ai::Analytics::PerformanceAnalysisService).to receive(:new).and_call_original
      allow(Ai::Analytics::DashboardService).to receive(:new).and_call_original
    end

    context 'with ai.analytics.read permission' do
      it 'GET /recommendations succeeds with the real services' do
        get '/api/v1/ai/analytics/recommendations', headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to have_key('recommendations')
      end

      it 'GET /insights succeeds with the real services' do
        get '/api/v1/ai/analytics/insights', headers: headers, as: :json

        expect_success_response
        expect(json_response_data).to have_key('insights')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/agents/:agent_id' do
    let!(:agent) do
      create(:ai_agent, account: account, name: 'Test Agent', agent_type: 'assistant', status: 'active')
    end

    before do
      allow(metrics_service).to receive(:agent_specific_metrics).and_return({})
    end

    context 'with permission' do
      it 'returns agent-specific analytics' do
        get "/api/v1/ai/analytics/agents/#{agent.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('agent_analytics')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/reports' do
    before do
      allow(ReportRequest).to receive_message_chain(:where, :order, :page, :per)
        .and_return(double(map: [], current_page: 1, total_pages: 1,
                           total_count: 0, limit_value: 20))
    end

    context 'with permission' do
      it 'returns list of reports' do
        get '/api/v1/ai/analytics/reports',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('reports')
        expect(data).to have_key('pagination')
      end
    end
  end

  describe 'POST /api/v1/ai/analytics/reports' do
    let(:report) { create(:report_request, account: account, user: user, report_type: 'comprehensive_report') }

    before do
      allow(ReportRequest).to receive(:create!).and_return(report)
      allow(WorkerJobService).to receive(:enqueue_job)
    end

    context 'with ai.analytics.create permission' do
      it 'creates a new report request' do
        post '/api/v1/ai/analytics/reports',
             params: {
               report: {
                 template_id: 'comprehensive_report',
                 parameters: {}
               }
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/analytics/reports',
             params: { report: { template_id: 'comprehensive_report' } },
             headers: auth_headers_for(read_only_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/analytics/reports/:id' do
    let!(:report) do
      # Use 'pending' status which is valid for both model validation and database constraint
      create(:report_request, account: account, user: user, report_type: 'comprehensive_report', status: 'pending')
    end

    context 'with ai.analytics.manage permission' do
      it 'cancels the report' do
        delete "/api/v1/ai/analytics/reports/#{report.id}",
               headers: auth_headers_for(manage_user),
               as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Report cancelled successfully')
      end
    end
  end

  describe 'GET /api/v1/ai/analytics/reports/templates' do
    let(:templates) do
      [
        { id: 'executive_summary', name: 'Executive Summary' },
        { id: 'cost_analysis', name: 'Cost Analysis' }
      ]
    end

    before do
      allow(report_service).to receive(:available_reports).and_return(templates)
    end

    context 'with permission' do
      it 'returns available report templates' do
        get '/api/v1/ai/analytics/reports/templates',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('templates')
        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/analytics/export' do
    let(:export_data) do
      {
        dashboard: { total_executions: 1000 }
      }
    end

    before do
      allow(report_service).to receive(:generate).and_return(export_data)
      allow(report_service).to receive(:export).and_return('csv,data')
    end

    context 'with ai.analytics.export permission' do
      it 'exports analytics data as JSON' do
        post '/api/v1/ai/analytics/export',
             params: { format: 'json', export_type: 'dashboard' },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'exports analytics data as CSV' do
        post '/api/v1/ai/analytics/export',
             params: { format: 'csv', export_type: 'dashboard' },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('text/csv')
      end

      it 'rejects invalid format' do
        post '/api/v1/ai/analytics/export',
             params: { format: 'invalid' },
             headers: headers,
             as: :json

        expect_error_response('Invalid export format', 400)
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/analytics/export',
             params: { format: 'json' },
             headers: auth_headers_for(read_only_user),
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

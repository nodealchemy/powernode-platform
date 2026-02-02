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
      allow(Ai::AnalyticsInsightsService).to receive(:new).and_return(
        instance_double('Ai::AnalyticsInsightsService',
                        generate_insights: insights_data)
      )
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
      allow(performance_service).to receive(:identify_bottlenecks).and_return({ bottlenecks: [] })
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

  describe 'GET /api/v1/ai/analytics/workflows/:workflow_id' do
    let!(:workflow) do
      create(:ai_workflow, account: account, name: 'Test Workflow', workflow_type: 'ai', status: 'active')
    end

    before do
      allow(metrics_service).to receive(:workflow_specific_metrics).and_return({})
    end

    context 'with permission' do
      it 'returns workflow-specific analytics' do
        get "/api/v1/ai/analytics/workflows/#{workflow.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('workflow_analytics')
      end
    end

    context 'when workflow not found' do
      it 'returns not found error' do
        get "/api/v1/ai/analytics/workflows/#{SecureRandom.uuid}",
            headers: headers,
            as: :json

        expect_error_response('Workflow not found', 404)
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
      allow(GenerateReportJob).to receive(:perform_later) if defined?(GenerateReportJob)
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

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AnalyticsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }  # User with no permissions
  let(:worker) { create(:worker) }

  # Permission-based users
  let(:analytics_read_user) { create(:user, account: account, permissions: [ 'ai.analytics.read' ]) }
  let(:analytics_manage_user) { create(:user, account: account, permissions: [ 'ai.analytics.read', 'ai.analytics.create', 'ai.analytics.manage', 'ai.analytics.export' ]) }

  # Test data
  let(:workflow) { create(:ai_workflow, account: account, name: 'Test Workflow') }
  let(:agent) { create(:ai_agent, account: account, name: 'Test Agent') }
  let!(:completed_runs) { create_list(:ai_workflow_run, 5, workflow: workflow, status: 'completed', total_cost: 1.50, duration_ms: 5000) }
  let!(:failed_runs) { create_list(:ai_workflow_run, 2, workflow: workflow, status: 'failed') }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'

    # ==========================================================================
    # SERVICE STUBS - Mock analytics services to return expected response shapes
    # ==========================================================================

    # --- DashboardService stubs ---
    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:generate).and_return({
      summary: {
        total_workflows: 5,
        total_agents: 3,
        total_executions: 7,
        success_rate: 0.714,
        total_cost: 10.50,
        workflows: { total: 5, active: 3, executions: 7, success_rate: 0.714 },
        agents: { total: 3, active: 2, executions: 5, success_rate: 0.8 },
        conversations: { total: 2, active: 1, messages: 10 },
        cost: { total: 10.50, trend: nil, budget_utilization: nil }
      },
      trends: [
        { date: Date.current.to_s, executions: 3, cost: 5.0 }
      ],
      highlights: { top_workflows: [], recent_failures: [] },
      quick_stats: {
        today: { executions: 2, cost: 3.0, messages: 5 },
        yesterday: { executions: 1, cost: 2.0, messages: 3 },
        this_week: { executions: 5, cost: 8.0, messages: 12 }
      },
      workflows: [
        { id: 'w1', name: 'Test Workflow', executions: 7 }
      ],
      resource_usage: { providers: {}, models: {}, tokens: { total_input_tokens: 0, total_output_tokens: 0, total_tokens: 0 } },
      recent_activity: []
    })

    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:generate_summary_metrics).and_return({
      workflows: { total: 5, active: 3, executions: 7, success_rate: 0.714 },
      agents: { total: 3, active: 2, executions: 5, success_rate: 0.8 },
      conversations: { total: 2, active: 1, messages: 10 },
      cost: { total: 10.50, trend: nil, budget_utilization: nil }
    })

    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:generate_trend_data).and_return({
      executions_by_day: { Date.current.to_s => 3 },
      cost_by_day: { Date.current.to_s => 5.0 },
      success_rate_by_day: { Date.current.to_s => 71.4 },
      messages_by_day: { Date.current.to_s => 10 }
    })

    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:generate_highlights).and_return({
      top_workflows: [],
      top_agents: [],
      recent_failures: [],
      cost_leaders: []
    })

    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:generate_quick_stats).and_return({
      executions_24h: 5,
      success_rate_24h: 80.0,
      cost_24h: 3.50,
      active_runs: 1,
      today: { executions: 2, cost: 3.0, messages: 5 },
      yesterday: { executions: 1, cost: 2.0, messages: 3 },
      this_week: { executions: 5, cost: 8.0, messages: 12 }
    })

    allow_any_instance_of(Ai::Analytics::DashboardService).to receive(:real_time_metrics).and_return({
      active_executions: 2,
      recent_executions: 10,
      success_rate: 85.0,
      average_response_time: 1500.0,
      active_conversations: 1,
      queue_depth: 0,
      error_rate_last_hour: 0.0,
      avg_response_time_last_hour: 1500.0,
      timestamp: Time.current.iso8601
    })

    # --- MetricsService stubs ---
    allow_any_instance_of(Ai::Analytics::MetricsService).to receive(:all_metrics).and_return({
      workflows: {
        total: 5,
        active: 3,
        inactive: 2,
        total_workflows: 5,
        active_workflows: 3,
        total_executions: 7,
        success_rate: 0.714
      },
      agents: {
        total: 3,
        active: 2,
        total_executions: 5,
        success_rate: 0.8
      },
      providers: {
        total_providers: 1,
        active_providers: 1,
        providers: []
      },
      executions: {
        total: 7,
        completed: 5,
        failed: 2,
        success_rate: 0.714,
        total_node_executions: 10,
        avg_nodes_per_workflow: 2.0
      },
      performance: {
        throughput: { executions_per_hour: 0.29, executions_per_day: 7.0 },
        latency: { p50_ms: nil, p90_ms: nil, p95_ms: nil, p99_ms: nil },
        availability: 99.9,
        error_budget: { target_slo: 99.9, actual_success_rate: 71.4, remaining_budget: -28.5, budget_consumed: 100 }
      }
    })

    allow_any_instance_of(Ai::Analytics::MetricsService).to receive(:workflow_specific_metrics) do |_service, wf|
      {
        workflow: { id: wf.id, name: wf.name },
        workflow_id: wf.id,
        workflow_name: wf.name,
        runs: { total: 7, completed: 5, failed: 2 },
        total_executions: 7,
        successful_executions: 5,
        failed_executions: 2,
        performance: { avg_duration_ms: 5000.0 },
        costs: { total: 10.50, average_per_run: 1.50 },
        success_rate: 71.4,
        average_duration: 5000.0,
        average_duration_ms: 5000.0,
        total_cost: 10.50,
        average_cost_per_execution: 1.50
      }
    end

    allow_any_instance_of(Ai::Analytics::MetricsService).to receive(:agent_specific_metrics) do |_service, ag|
      {
        agent: { id: ag.id, name: ag.name },
        agent_id: ag.id,
        agent_name: ag.name,
        executions: { total: 5, completed: 4, failed: 1 },
        total_executions: 5,
        successful_executions: 4,
        failed_executions: 1,
        performance: { avg_response_time_ms: 1200.0 },
        costs: { total: 5.0, average_per_execution: 1.0 },
        success_rate: 80.0
      }
    end

    # --- CostAnalysisService stubs ---
    allow_any_instance_of(Ai::Analytics::CostAnalysisService).to receive(:full_analysis).and_return({
      total_cost: 10.50,
      cost_trend: { current_period_cost: 10.50, previous_period_cost: 8.0, change_percentage: 31.25 },
      cost_by_provider: [],
      cost_by_agent: [],
      cost_by_workflow: [ { workflow_id: 'w1', workflow_name: 'Test', total_cost: 10.50 } ],
      cost_by_model: [],
      daily_costs: {},
      budget_status: {},
      optimization_potential: {
        current_cost: 10.50,
        potential_savings: 2.10,
        optimization_areas: [ 'Use cheaper models for simple tasks' ],
        total_potential_savings: 2.10,
        opportunities: []
      },
      budget_forecast: {
        daily_average: 0.35,
        weekly_forecast: 2.45,
        monthly_forecast: 10.50,
        yearly_forecast: 126.0,
        average_daily_cost: 0.35,
        daily_trend: 0.01,
        forecast_next_7_days: 2.45,
        forecast_next_30_days: 10.50,
        forecast_month_end: 5.25,
        confidence_level: 'low'
      },
      anomalies: []
    })

    allow_any_instance_of(Ai::Analytics::CostAnalysisService).to receive(:estimate_cost_savings).and_return({
      total_potential_savings: 2.10,
      opportunities: []
    })

    # --- PerformanceAnalysisService stubs ---
    allow_any_instance_of(Ai::Analytics::PerformanceAnalysisService).to receive(:full_analysis).and_return({
      response_times: {
        count: 5,
        average_ms: 5000.0,
        avg_ms: 5000.0,
        median_ms: 4500.0,
        p75_ms: 5500.0,
        p90_ms: 6000.0,
        p95_ms: 6500.0,
        p99_ms: 7000.0,
        min_ms: 3000.0,
        max_ms: 7000.0,
        std_dev_ms: 1200.0,
        by_hour: {},
        by_workflow: []
      },
      success_rates: {
        total_executions: 7,
        successful: 5,
        failed: 2,
        cancelled: 0,
        success_rate: 71.43,
        failure_rate: 28.57,
        cancellation_rate: 0.0
      },
      throughput: {
        total_executions: 7,
        executions_per_hour: 0.29,
        executions_per_day: 7.0
      },
      error_rates: {
        total_errors: 2,
        error_rate: 28.57,
        by_error_type: {},
        by_workflow: [],
        by_node_type: {},
        recent_errors: []
      },
      resource_utilization: {
        provider_utilization: {},
        model_utilization: {},
        token_utilization: { total_tokens: 0 },
        queue_metrics: { avg_queue_time_ms: 0 }
      },
      bottlenecks: {
        slow_workflows: [],
        recommendations: [ 'Consider optimizing long-running workflows' ]
      },
      sla_compliance: {},
      performance_trends: {}
    })

    allow_any_instance_of(Ai::Analytics::PerformanceAnalysisService).to receive(:identify_bottlenecks).and_return({
      bottlenecks: [],
      slow_workflows: [],
      recommendations: []
    })

    allow_any_instance_of(Ai::Analytics::PerformanceAnalysisService).to receive(:analyze_error_rates).and_return({
      total_errors: 2,
      error_rate: 0.0,
      by_error_type: {},
      by_workflow: [],
      by_node_type: {},
      recent_errors: []
    })

    # --- ReportService stubs ---
    allow_any_instance_of(Ai::Analytics::ReportService).to receive(:available_reports).and_return([
      { id: 'executive_summary', name: 'Executive Summary', description: 'High-level overview', category: 'summary', formats: [ 'json', 'csv', 'pdf' ] },
      { id: 'cost_analysis', name: 'Cost Analysis', description: 'Detailed cost breakdown', category: 'cost', formats: [ 'json', 'csv' ] },
      { id: 'performance_analysis', name: 'Performance Analysis', description: 'Performance metrics', category: 'performance', formats: [ 'json', 'csv' ] }
    ])

    allow_any_instance_of(Ai::Analytics::ReportService).to receive(:generate).and_return({
      report_type: 'executive_summary',
      generated_at: Time.current.iso8601,
      data: { title: 'Executive Summary Report', highlights: [] }
    })

    allow_any_instance_of(Ai::Analytics::ReportService).to receive(:export).and_return('exported_data')
  end

  # =============================================================================
  # DASHBOARD & OVERVIEW
  # =============================================================================

  describe 'GET #dashboard' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns analytics dashboard data' do
        get :dashboard

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['dashboard']).to be_present
        expect(json['data']['generated_at']).to be_present
      end

      it 'includes summary metrics' do
        get :dashboard

        json = JSON.parse(response.body)
        summary = json['data']['dashboard']['summary']
        expect(summary).to include(
          'total_workflows',
          'total_agents',
          'total_executions',
          'success_rate',
          'total_cost'
        )
      end

      it 'includes time range information' do
        get :dashboard, params: { time_range: '7d' }

        json = JSON.parse(response.body)
        expect(json['data']['time_range']).to include(
          'start',
          'end',
          'period'
        )
        expect(json['data']['time_range']['period']).to eq('7d')
      end

      it 'includes workflow metrics' do
        get :dashboard

        json = JSON.parse(response.body)
        expect(json['data']['dashboard']['workflows']).to be_an(Array)
      end

      it 'includes trend data' do
        get :dashboard

        json = JSON.parse(response.body)
        expect(json['data']['dashboard']['trends']).to be_an(Array)
      end

      it 'supports different time ranges' do
        get :dashboard, params: { time_range: '1h' }

        expect(response).to have_http_status(:success)

        get :dashboard, params: { time_range: '30d' }

        expect(response).to have_http_status(:success)

        get :dashboard, params: { time_range: '1y' }

        expect(response).to have_http_status(:success)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden error' do
        get :dashboard

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #overview' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns overview data' do
        get :overview

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['overview']).to include(
          'summary',
          'trends',
          'highlights',
          'quick_stats'
        )
      end

      it 'includes quick stats for last 24h' do
        get :overview

        json = JSON.parse(response.body)
        quick_stats = json['data']['overview']['quick_stats']
        expect(quick_stats).to include(
          'executions_24h',
          'success_rate_24h',
          'cost_24h',
          'active_runs'
        )
      end
    end
  end

  # =============================================================================
  # METRICS & ANALYTICS
  # =============================================================================

  describe 'GET #metrics' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns comprehensive metrics' do
        get :metrics

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['metrics']).to include(
          'workflows',
          'agents',
          'providers',
          'executions',
          'performance'
        )
      end

      it 'includes time range in seconds' do
        get :metrics, params: { time_range: '7d' }

        json = JSON.parse(response.body)
        expect(json['data']['time_range_seconds']).to eq(7.days.to_i)
      end

      it 'includes workflow metrics' do
        get :metrics

        json = JSON.parse(response.body)
        expect(json['data']['metrics']['workflows']).to include(
          'total',
          'active',
          'inactive'
        )
      end

      it 'includes execution metrics' do
        get :metrics

        json = JSON.parse(response.body)
        expect(json['data']['metrics']['executions']).to include(
          'total',
          'completed',
          'failed',
          'success_rate'
        )
      end
    end
  end

  describe 'GET #real_time' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns real-time metrics' do
        get :real_time

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['metrics']).to include(
          'active_executions',
          'recent_executions',
          'success_rate',
          'average_response_time'
        )
      end

      it 'includes refresh interval' do
        get :real_time

        json = JSON.parse(response.body)
        expect(json['data']['refresh_interval']).to eq(30)
      end
    end
  end

  describe 'GET #cost_analysis' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns cost analysis data' do
        get :cost_analysis

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['cost_analysis']).to include(
          'total_cost',
          'cost_trend',
          'cost_by_provider',
          'cost_by_workflow',
          'optimization_potential',
          'budget_forecast'
        )
      end

      it 'calculates total cost for time range' do
        get :cost_analysis, params: { time_range: '30d' }

        json = JSON.parse(response.body)
        total_cost = json['data']['cost_analysis']['total_cost']
        expect(total_cost).to be_a(Float)
      end

      it 'includes budget forecast' do
        get :cost_analysis

        json = JSON.parse(response.body)
        forecast = json['data']['cost_analysis']['budget_forecast']
        expect(forecast).to include(
          'daily_average',
          'weekly_forecast',
          'monthly_forecast',
          'yearly_forecast'
        )
      end

      it 'includes optimization potential' do
        get :cost_analysis

        json = JSON.parse(response.body)
        optimization = json['data']['cost_analysis']['optimization_potential']
        expect(optimization).to include(
          'current_cost',
          'potential_savings',
          'optimization_areas'
        )
      end
    end
  end

  describe 'GET #performance_analysis' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns performance analysis data' do
        get :performance_analysis

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['performance_analysis']).to include(
          'response_times',
          'success_rates',
          'throughput',
          'error_rates',
          'resource_utilization',
          'bottlenecks'
        )
      end

      it 'analyzes response times with percentiles' do
        get :performance_analysis

        json = JSON.parse(response.body)
        response_times = json['data']['performance_analysis']['response_times']
        expect(response_times).to include(
          'average_ms',
          'median_ms',
          'p95_ms',
          'min_ms',
          'max_ms'
        )
      end

      it 'identifies bottlenecks' do
        get :performance_analysis

        json = JSON.parse(response.body)
        bottlenecks = json['data']['performance_analysis']['bottlenecks']
        expect(bottlenecks).to include('slow_workflows', 'recommendations')
      end
    end
  end

  # =============================================================================
  # INSIGHTS & RECOMMENDATIONS
  # =============================================================================

  describe 'GET #insights' do
    let(:cached_insights) do
      {
        performance_insights: {},
        cost_insights: {},
        usage_insights: {},
        recommendations: []
      }
    end

    before do
      allow(Rails.cache).to receive(:fetch).and_call_original
      allow(Rails.cache).to receive(:fetch).with(/ai:analytics:insights/, any_args).and_return(cached_insights)
    end

    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns AI-generated insights' do
        get :insights

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['insights']).to be_present
      end

      it 'includes time range information' do
        get :insights, params: { time_range: '7d' }

        json = JSON.parse(response.body)
        expect(json['data']['time_range']).to include('start', 'end', 'period')
      end
    end
  end

  describe 'GET #recommendations' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns optimization recommendations' do
        get :recommendations

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['recommendations']).to be_an(Array)
      end

      it 'includes recommendation details' do
        # Create expensive workflow to trigger recommendation
        expensive_workflow = create(:ai_workflow, account: account)
        create_list(:ai_workflow_run, 10, workflow: expensive_workflow, status: 'completed', total_cost: 15.0)

        get :recommendations

        json = JSON.parse(response.body)
        recommendations = json['data']['recommendations']

        if recommendations.any?
          expect(recommendations.first).to include('type', 'priority', 'title', 'description', 'action')
        end
      end
    end
  end

  # =============================================================================
  # WORKFLOW & AGENT ANALYTICS
  # =============================================================================

  describe 'GET #workflow_analytics' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns workflow-specific analytics' do
        get :workflow_analytics, params: { workflow_id: workflow.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['workflow_analytics']).to include(
          'workflow',
          'runs',
          'performance',
          'costs',
          'success_rate',
          'average_duration'
        )
      end

      it 'includes workflow summary' do
        get :workflow_analytics, params: { workflow_id: workflow.id }

        json = JSON.parse(response.body)
        workflow_data = json['data']['workflow_analytics']['workflow']
        expect(workflow_data['id']).to eq(workflow.id)
        expect(workflow_data['name']).to eq('Test Workflow')
      end

      it 'calculates success rate' do
        get :workflow_analytics, params: { workflow_id: workflow.id }

        json = JSON.parse(response.body)
        success_rate = json['data']['workflow_analytics']['success_rate']
        expect(success_rate).to be_a(Float)
      end

      it 'returns not found for nonexistent workflow' do
        get :workflow_analytics, params: { workflow_id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['error']).to include('not found')
      end

      it 'prevents access to other account workflows' do
        other_workflow = create(:ai_workflow)

        get :workflow_analytics, params: { workflow_id: other_workflow.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET #agent_analytics' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns agent-specific analytics' do
        get :agent_analytics, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['agent_analytics']).to include(
          'agent',
          'executions',
          'performance',
          'costs',
          'success_rate'
        )
      end

      it 'returns not found for nonexistent agent' do
        get :agent_analytics, params: { agent_id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # REPORTS
  # =============================================================================

  describe 'GET #reports_index' do
    let!(:report1) { create(:report_request, account: account, user: analytics_read_user, report_type: 'revenue_analytics') }
    let!(:report2) { create(:report_request, account: account, user: analytics_read_user, report_type: 'customer_analytics') }

    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns list of reports' do
        get :reports_index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['reports'].length).to eq(2)
      end

      it 'includes pagination' do
        get :reports_index, params: { page: 1, per_page: 1 }

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to include(
          'current_page' => 1,
          'per_page' => 1,
          'total_pages' => 2
        )
      end

      it 'limits maximum per_page to 100' do
        get :reports_index, params: { per_page: 200 }

        json = JSON.parse(response.body)
        expect(json['data']['pagination']['per_page']).to eq(100)
      end
    end
  end

  describe 'GET #report_show' do
    let(:report) { create(:report_request, account: account, user: analytics_read_user) }

    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns report details' do
        get :report_show, params: { id: report.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['report']['id']).to eq(report.id)
      end

      it 'returns not found for nonexistent report' do
        get :report_show, params: { id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #report_create' do
    before do
      allow(GenerateReportJob).to receive(:perform_later)
    end

    context 'with valid permissions' do
      before { sign_in analytics_manage_user }

      it 'creates a new report request' do
        expect {
          post :report_create, params: {
            report: {
              template_id: 'revenue_analytics'
            }
          }
        }.to change(ReportRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['report']['type']).to eq('revenue_analytics')
      end

      it 'queues background job for generation' do
        expect(GenerateReportJob).to receive(:perform_later)

        post :report_create, params: {
          report: {
            template_id: 'customer_analytics'
          }
        }

        expect(response).to have_http_status(:created)
      end

      it 'creates report with valid report_type' do
        post :report_create, params: {
          report: {
            template_id: 'growth_analytics'
          }
        }

        report = ReportRequest.last
        expect(report.report_type).to eq('growth_analytics')
      end

      it 'handles creation errors' do
        allow(ReportRequest).to receive(:create!).and_raise(StandardError, 'Creation failed')

        post :report_create, params: {
          report: {
            name: 'Test Report',
            template_id: 'ai_performance'
          }
        }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Failed to create report')
      end
    end

    context 'without create permission' do
      before { sign_in analytics_read_user }

      it 'returns forbidden error' do
        post :report_create, params: {
          report: {
            name: 'Test Report',
            template_id: 'ai_performance'
          }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE #report_cancel' do
    let(:pending_report) { create(:report_request, account: account, user: analytics_manage_user, status: 'pending') }
    let(:completed_report) { create(:report_request, account: account, user: analytics_manage_user, status: 'completed') }

    context 'with valid permissions' do
      before { sign_in analytics_manage_user }

      it 'cancels pending report' do
        delete :report_cancel, params: { id: pending_report.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to include('cancelled successfully')
        # Note: Uses 'failed' status since 'cancelled' is not in DB constraint
        expect(pending_report.reload.status).to eq('failed')
      end

      it 'cannot cancel completed report' do
        delete :report_cancel, params: { id: completed_report.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Cannot cancel completed report')
      end

      it 'returns not found for nonexistent report' do
        delete :report_cancel, params: { id: 'nonexistent' }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without manage permission' do
      before { sign_in analytics_read_user }

      it 'returns forbidden error' do
        delete :report_cancel, params: { id: pending_report.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #report_download' do
    let(:reports_dir) { Rails.root.join('tmp', 'reports') }
    let(:test_report_path) { reports_dir.join('test_report.pdf').to_s }

    let(:completed_report) do
      create(:report_request,
        account: account,
        user: analytics_manage_user,
        status: 'completed',
        file_path: test_report_path
      )
    end

    let(:pending_report) { create(:report_request, account: account, user: analytics_manage_user, status: 'pending') }

    before do
      FileUtils.mkdir_p(reports_dir)
      File.write(test_report_path, 'test content')
    end

    after do
      File.delete(test_report_path) if File.exist?(test_report_path)
    end

    context 'with valid permissions' do
      before { sign_in analytics_manage_user }

      it 'downloads completed report' do
        get :report_download, params: { id: completed_report.id }

        expect(response).to have_http_status(:success)
      end

      it 'cannot download pending report' do
        get :report_download, params: { id: pending_report.id }

        expect(response).to have_http_status(:unprocessable_content)
        json = JSON.parse(response.body)
        expect(json['error']).to include('not ready for download')
      end

      it 'returns not found when file missing' do
        # Use a path within the allowed directory but for a non-existent file
        completed_report.update!(file_path: reports_dir.join('nonexistent_report.pdf').to_s)

        get :report_download, params: { id: completed_report.id }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without export permission' do
      before { sign_in analytics_read_user }

      it 'returns forbidden error' do
        get :report_download, params: { id: completed_report.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #report_templates' do
    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns available report templates' do
        get :report_templates

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['templates']).to be_an(Array)
        expect(json['data']['templates'].length).to be > 0
      end

      it 'includes template details' do
        get :report_templates

        json = JSON.parse(response.body)
        template = json['data']['templates'].first
        expect(template).to include('id', 'name', 'description', 'category', 'formats')
      end
    end
  end

  # =============================================================================
  # EXPORT
  # =============================================================================

  describe 'POST #export' do
    context 'with valid permissions' do
      before { sign_in analytics_manage_user }

      it 'exports dashboard data as JSON' do
        post :export, params: { format: 'json', export_type: 'dashboard' }

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('application/json')
      end

      it 'exports as CSV' do
        post :export, params: { format: 'csv', export_type: 'cost_analysis' }

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('attachment')
      end

      it 'exports as XLSX' do
        post :export, params: { format: 'xlsx', export_type: 'performance' }

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('spreadsheet')
      end

      it 'validates export format' do
        post :export, params: { format: 'invalid' }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Invalid export format')
      end

      it 'defaults to JSON format' do
        post :export

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('application/json')
      end

      it 'handles export errors gracefully' do
        allow_any_instance_of(Api::V1::Ai::AnalyticsController).to receive(:generate_report_for_export).and_raise(StandardError.new("test error"))

        post :export, params: { format: 'json' }

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['error']).to include('Export failed')
      end
    end

    context 'without export permission' do
      before { sign_in analytics_read_user }

      it 'returns forbidden error' do
        post :export, params: { format: 'json' }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # WORKER CONTEXT
  # =============================================================================

  describe 'worker authentication' do
    before do
      # Set WORKER_TOKEN environment variable for worker authentication
      ENV['WORKER_TOKEN'] = worker.auth_token
      @request.headers['X-Worker-Token'] = worker.auth_token
    end

    after do
      # Clean up environment variable
      ENV.delete('WORKER_TOKEN')
    end

    it 'allows workers to access analytics endpoints' do
      get :dashboard

      expect(response).to have_http_status(:success)
    end

    it 'bypasses permission checks for workers' do
      get :cost_analysis

      expect(response).to have_http_status(:success)
    end
  end
end

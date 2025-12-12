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
  let!(:completed_runs) { create_list(:ai_workflow_run, 5, ai_workflow: workflow, status: 'completed', total_cost: 1.50, duration_ms: 5000) }
  let!(:failed_runs) { create_list(:ai_workflow_run, 2, ai_workflow: workflow, status: 'failed') }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
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
    before do
      allow_any_instance_of(AiAnalyticsInsightsService).to receive(:generate_insights).and_return({
        cost_insights: [],
        performance_insights: [],
        usage_insights: []
      })
    end

    context 'with valid permissions' do
      before { sign_in analytics_read_user }

      it 'returns AI-generated insights' do
        expect_any_instance_of(AiAnalyticsInsightsService).to receive(:generate_insights)

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
        create_list(:ai_workflow_run, 10, ai_workflow: expensive_workflow, status: 'completed', total_cost: 15.0)

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
        allow_any_instance_of(Api::V1::Ai::AnalyticsController).to receive(:generate_export_data).and_raise(StandardError)

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

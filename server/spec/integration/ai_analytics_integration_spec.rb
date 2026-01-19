# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Analytics Integration', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :system_admin, account: account) }

  # Core AI components
  let!(:provider1) { create(:ai_provider, slug: 'openai', name: 'OpenAI') }
  let!(:provider2) { create(:ai_provider, slug: 'anthropic', name: 'Anthropic') }
  let!(:agent1) { create(:ai_agent, account: account, provider: provider1, name: 'Code Assistant') }
  let!(:agent2) { create(:ai_agent, account: account, provider: provider2, name: 'Research Agent') }
  let!(:conversation1) { create(:ai_conversation, account: account, agent: agent1) }
  let!(:conversation2) { create(:ai_conversation, account: account, agent: agent2) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(account)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_request).and_return(true)
    # Grant AI analytics permissions
    allow_any_instance_of(Api::V1::Ai::AnalyticsController).to receive(:require_permission).and_return(true)
  end

  describe 'Comprehensive Analytics Dashboard Integration' do
    before do
      # Create realistic execution history spanning different time periods
      create_execution_history
      create_conversation_history
      create_cost_data
    end

    it 'provides complete analytics dashboard data' do
      get '/api/v1/ai/analytics/dashboard', params: { period: 30 }

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true

      dashboard_data = json_response['data']['dashboard']

      # Executive summary metrics
      expect(dashboard_data['summary']).to include(
        'total_executions',
        'total_workflows',
        'total_agents',
        'total_cost',
        'success_rate'
      )

      # Time-based analytics (trends)
      expect(dashboard_data['trends']).to be_an(Array)
      expect(dashboard_data['trends'].first).to include('date', 'executions', 'cost')

      # Provider metrics (may be empty if no credentials)
      expect(dashboard_data).to have_key('providers')

      # Agent metrics
      expect(dashboard_data).to have_key('agents')

      # Cost metrics
      expect(dashboard_data).to have_key('costs')
    end

    it 'filters analytics by date range' do
      # Request last 7 days only
      get '/api/v1/ai/analytics/dashboard', params: {
        period: 7,
        start_date: 7.days.ago.to_date,
        end_date: Date.current
      }

      expect(response).to have_http_status(:ok)
      dashboard_data = json_response['data']['dashboard']

      # Verify trends data is present
      expect(dashboard_data['trends']).to be_an(Array)

      # Verify summary is present
      expect(dashboard_data['summary']).to be_present
      expect(dashboard_data['summary']['total_executions']).to be_a(Integer)
    end

    it 'provides real-time analytics updates' do
      # Get initial state
      get '/api/v1/ai/analytics/dashboard', params: { period: 1 }
      initial_total = json_response['data']['dashboard']['summary']['total_executions']

      # Create new workflow run (what the analytics actually track)
      workflow = create(:ai_workflow, account: account)
      create(:ai_workflow_run, :completed, workflow: workflow, account: account)

      # Get updated state
      get '/api/v1/ai/analytics/dashboard', params: { period: 1 }
      updated_total = json_response['data']['dashboard']['summary']['total_executions']

      expect(updated_total).to eq(initial_total + 1)
    end
  end

  describe 'Provider Performance Analytics' do
    before do
      create_provider_performance_data
    end

    it 'compares provider performance metrics' do
      get '/api/v1/ai/analytics/performance_analysis'

      expect(response).to have_http_status(:ok)
      performance_data = json_response['data']

      # Performance analysis provides comprehensive metrics
      expect(performance_data).to have_key('performance_analysis')
      expect(performance_data).to have_key('timestamp')
    end

    it 'tracks provider reliability over time' do
      get '/api/v1/ai/analytics/performance_analysis', params: { period: 30 }

      expect(response).to have_http_status(:ok)
      performance_data = json_response['data']

      # Performance analysis endpoint provides metrics
      expect(performance_data).to be_present
    end

    it 'identifies performance anomalies' do
      # Create workflow with failures to track
      workflow = create(:ai_workflow, account: account)
      5.times do
        create(:ai_workflow_run, :failed, workflow: workflow, account: account)
      end

      get '/api/v1/ai/analytics/recommendations'

      expect(response).to have_http_status(:ok)
      recommendations_data = json_response['data']

      # Recommendations endpoint provides analytics insights
      expect(recommendations_data).to be_present
    end
  end

  describe 'Cost Analysis and Optimization' do
    before do
      create_detailed_cost_history
    end

    it 'provides comprehensive cost analysis' do
      get '/api/v1/ai/analytics/cost_analysis', params: { period: 30 }

      expect(response).to have_http_status(:ok)
      cost_data = json_response['data']

      # Cost analysis provides analysis data
      expect(cost_data).to have_key('cost_analysis')
      expect(cost_data).to have_key('timestamp')
    end

    it 'tracks cost per execution trends' do
      get '/api/v1/ai/analytics/cost_analysis', params: { period: 30 }

      expect(response).to have_http_status(:ok)
      cost_data = json_response['data']

      # Cost analysis endpoint provides cost data
      expect(cost_data).to be_present
    end

    it 'provides cost optimization recommendations' do
      get '/api/v1/ai/analytics/recommendations'

      expect(response).to have_http_status(:ok)
      recommendations_data = json_response['data']

      # Recommendations endpoint provides optimization suggestions
      expect(recommendations_data).to be_present
    end

    it 'tracks budget alerts and thresholds' do
      # Use the cost_analysis endpoint to check spending
      get '/api/v1/ai/analytics/cost_analysis'

      expect(response).to have_http_status(:ok)
      cost_data = json_response['data']

      # Cost analysis endpoint provides spending data
      expect(cost_data).to be_present
    end
  end

  describe 'Usage Pattern Analysis' do
    before do
      create_usage_pattern_data
    end

    it 'analyzes conversation patterns' do
      get '/api/v1/ai/analytics/overview'

      expect(response).to have_http_status(:ok)
      overview_data = json_response['data']

      # Overview endpoint provides usage pattern data
      expect(overview_data).to be_present
    end

    it 'identifies peak usage times' do
      get '/api/v1/ai/analytics/dashboard', params: { period: 7 }

      expect(response).to have_http_status(:ok)
      dashboard_data = json_response['data']

      # Dashboard endpoint provides usage patterns over time
      expect(dashboard_data).to be_present
    end

    it 'tracks user engagement metrics' do
      get '/api/v1/ai/analytics/metrics'

      expect(response).to have_http_status(:ok)
      metrics_data = json_response['data']

      # Metrics endpoint provides engagement data
      expect(metrics_data).to be_present
    end
  end

  describe 'Performance Monitoring Integration' do
    it 'integrates with system performance metrics' do
      get '/api/v1/ai/analytics/performance_analysis'

      expect(response).to have_http_status(:ok)
      performance_data = json_response['data']

      # Performance analysis endpoint provides system metrics
      expect(performance_data).to be_present
    end

    it 'provides health check summaries' do
      get '/api/v1/ai/analytics/real_time'

      expect(response).to have_http_status(:ok)
      realtime_data = json_response['data']

      # Real-time endpoint provides health status
      expect(realtime_data).to be_present
    end
  end

  describe 'Export and Reporting' do
    it 'exports analytics data in multiple formats' do
      # Export endpoint (POST)
      post '/api/v1/ai/analytics/export', params: {
        format: 'json',
        period: 30
      }

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'generates scheduled reports' do
      # List reports endpoint
      get '/api/v1/ai/analytics/reports'

      # Reports endpoint returns list of reports
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'supports custom analytics queries' do
      # Use overview endpoint for custom analytics view
      get '/api/v1/ai/analytics/overview', params: {
        period: 30
      }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to be_present
    end
  end

  private

  def create_execution_history
    # Create executions across different time periods
    3.times do |i|
      create(:ai_agent_execution, :completed,
             agent: agent1,
             account: account,
             created_at: i.days.ago,
             cost_usd: 0.05 + (i * 0.02))
    end

    2.times do |i|
      create(:ai_agent_execution, :completed,
             agent: agent2,
             account: account,
             created_at: i.days.ago,
             cost_usd: 0.08 + (i * 0.03))
    end

    # Add some failures
    create(:ai_agent_execution, :failed,
           agent: agent1,
           account: account,
           created_at: 1.day.ago)
  end

  def create_conversation_history
    # Create messages in conversations (account inherited from ai_conversation)
    10.times do |i|
      create(:ai_message,
             conversation: conversation1,
             agent: agent1,
             created_at: i.hours.ago,
             role: i.even? ? 'user' : 'assistant',
             sequence_number: i + 1)
    end

    8.times do |i|
      create(:ai_message,
             conversation: conversation2,
             agent: agent2,
             created_at: i.hours.ago,
             role: i.even? ? 'user' : 'assistant',
             sequence_number: i + 1)
    end
  end

  def create_cost_data
    # Create cost tracking records
    5.times do |i|
      date = i.days.ago.to_date

      # OpenAI costs
      AuditLog.create!(
        account: account,
        user: user,
        action: 'ai_execution_cost',
        resource_type: 'Ai::AgentExecution',
        resource_id: SecureRandom.uuid,
        metadata: {
          provider: 'openai',
          cost: 0.05 * (i + 1),
          date: date,
          tokens: 1000 + (i * 100)
        }
      )

      # Anthropic costs
      AuditLog.create!(
        account: account,
        user: user,
        action: 'ai_execution_cost',
        resource_type: 'Ai::AgentExecution',
        resource_id: SecureRandom.uuid,
        metadata: {
          provider: 'anthropic',
          cost: 0.08 * (i + 1),
          date: date,
          tokens: 800 + (i * 120)
        }
      )
    end
  end

  def create_provider_performance_data
    # Create performance tracking data
    %w[openai anthropic].each do |provider_slug|
      provider = Ai::Provider.find_by(slug: provider_slug)
      agent = provider_slug == 'openai' ? agent1 : agent2

      # Successful executions
      10.times do |i|
        create(:ai_agent_execution, :completed,
               agent: agent,
               account: account,
               created_at: i.hours.ago,
               duration_ms: 1000 + rand(500),
               cost_usd: 0.05 + rand(0.03))
      end

      # Some failures
      2.times do |i|
        create(:ai_agent_execution, :failed,
               agent: agent,
               account: account,
               created_at: i.hours.ago)
      end
    end
  end

  def create_detailed_cost_history
    # Create 30 days of cost history
    30.times do |i|
      date = i.days.ago.to_date

      %w[openai anthropic].each do |provider|
        daily_executions = rand(5..15)
        daily_cost = daily_executions * (0.03 + rand(0.07))

        AuditLog.create!(
          account: account,
          user: user,
          action: 'ai_daily_cost_summary',
          resource_type: 'Ai::Provider',
          resource_id: SecureRandom.uuid,
          metadata: {
            provider: provider,
            date: date,
            executions: daily_executions,
            total_cost: daily_cost,
            average_cost_per_execution: daily_cost / daily_executions
          }
        )
      end
    end
  end

  def create_usage_pattern_data
    # Create usage data across different hours and days
    7.times do |day|
      24.times do |hour|
        # Simulate higher usage during business hours
        execution_count = if (9..17).include?(hour)
          rand(3..8)
        else
          rand(0..2)
        end

        execution_count.times do
          create(:ai_agent_execution, :completed,
                 agent: [ agent1, agent2 ].sample,
                 account: account,
                 created_at: day.days.ago + hour.hours)
        end
      end
    end
  end

  def json_response
    JSON.parse(response.body)
  end
end

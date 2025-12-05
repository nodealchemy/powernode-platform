# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Analytics Integration', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :system_admin, account: account) }
  
  # Core AI components
  let!(:provider1) { create(:ai_provider, slug: 'openai', name: 'OpenAI') }
  let!(:provider2) { create(:ai_provider, slug: 'anthropic', name: 'Anthropic') }
  let!(:agent1) { create(:ai_agent, account: account, ai_provider: provider1, name: 'Code Assistant') }
  let!(:agent2) { create(:ai_agent, account: account, ai_provider: provider2, name: 'Research Agent') }
  let!(:conversation1) { create(:ai_conversation, account: account, ai_agent: agent1) }
  let!(:conversation2) { create(:ai_conversation, account: account, ai_agent: agent2) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:current_account).and_return(account)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_request).and_return(true)
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
      
      dashboard_data = json_response['data']
      
      # Executive summary metrics
      expect(dashboard_data['summary']).to include(
        'total_executions',
        'total_conversations',
        'total_messages',
        'total_cost',
        'success_rate',
        'average_response_time'
      )
      
      # Time-based analytics
      expect(dashboard_data['timeline']).to be_an(Array)
      expect(dashboard_data['timeline'].first).to include('date', 'executions', 'messages', 'cost')
      
      # Provider performance comparison
      expect(dashboard_data['provider_comparison']).to be_an(Array)
      expect(dashboard_data['provider_comparison'].size).to eq(2)
      
      # Agent utilization metrics
      expect(dashboard_data['agent_utilization']).to be_an(Array)
      expect(dashboard_data['agent_utilization'].size).to eq(2)
      
      # Cost breakdown
      expect(dashboard_data['cost_breakdown']).to include(
        'by_provider',
        'by_agent',
        'by_conversation_type',
        'projected_monthly_cost'
      )
    end

    it 'filters analytics by date range' do
      # Request last 7 days only
      get '/api/v1/ai/analytics/dashboard', params: { 
        period: 7,
        start_date: 7.days.ago.to_date,
        end_date: Date.current
      }
      
      expect(response).to have_http_status(:ok)
      dashboard_data = json_response['data']
      
      # Verify timeline respects date filter
      expect(dashboard_data['timeline'].size).to be <= 7
      
      # Verify data only includes recent executions
      total_executions = dashboard_data['summary']['total_executions']
      expect(total_executions).to be < 20 # Should be less than full history
    end

    it 'provides real-time analytics updates' do
      # Get initial state
      get '/api/v1/ai/analytics/dashboard', params: { period: 1 }
      initial_total = json_response['data']['summary']['total_executions']
      
      # Create new execution
      create(:ai_agent_execution, :completed, 
             ai_agent: agent1, 
             account: account,
             created_at: Time.current)
      
      # Get updated state
      get '/api/v1/ai/analytics/dashboard', params: { period: 1 }
      updated_total = json_response['data']['summary']['total_executions']
      
      expect(updated_total).to eq(initial_total + 1)
    end
  end

  describe 'Provider Performance Analytics' do
    before do
      create_provider_performance_data
    end

    it 'compares provider performance metrics' do
      get '/api/v1/ai/analytics/provider_performance'
      
      expect(response).to have_http_status(:ok)
      performance_data = json_response['data']
      
      expect(performance_data['providers']).to be_an(Array)
      expect(performance_data['providers'].size).to eq(2)
      
      openai_stats = performance_data['providers'].find { |p| p['slug'] == 'openai' }
      expect(openai_stats).to include(
        'total_executions',
        'success_rate',
        'average_response_time',
        'total_cost',
        'requests_per_minute',
        'error_rate'
      )
      
      # Verify benchmarking
      expect(performance_data['benchmark']).to include(
        'fastest_provider',
        'most_reliable_provider',
        'most_cost_effective_provider'
      )
    end

    it 'tracks provider reliability over time' do
      get '/api/v1/ai/analytics/provider_reliability', params: { period: 30 }
      
      expect(response).to have_http_status(:ok)
      reliability_data = json_response['data']
      
      expect(reliability_data['timeline']).to be_an(Array)
      expect(reliability_data['timeline'].first).to include(
        'date',
        'provider_stats'
      )
      
      # Each day should have stats for each provider
      daily_stats = reliability_data['timeline'].first['provider_stats']
      expect(daily_stats).to be_a(Hash)
      expect(daily_stats.keys).to include('openai', 'anthropic')
    end

    it 'identifies performance anomalies' do
      # Create anomalous data
      create_list(:ai_agent_execution, 5, :failed, 
                 ai_agent: agent1, 
                 account: account,
                 created_at: 1.hour.ago)
      
      get '/api/v1/ai/analytics/anomalies', params: { period: 1 }
      
      expect(response).to have_http_status(:ok)
      anomaly_data = json_response['data']
      
      expect(anomaly_data['anomalies']).to be_an(Array)
      expect(anomaly_data['anomalies']).not_to be_empty
      
      failure_anomaly = anomaly_data['anomalies'].find { |a| a['type'] == 'high_failure_rate' }
      expect(failure_anomaly).to be_present
      expect(failure_anomaly['provider_slug']).to eq('openai')
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
      
      # Cost breakdown by multiple dimensions
      expect(cost_data['breakdown']).to include(
        'by_provider',
        'by_agent',
        'by_conversation_type',
        'by_time_period'
      )
      
      # Cost optimization insights
      expect(cost_data['insights']).to include(
        'highest_cost_agents',
        'cost_per_execution_trend',
        'optimization_recommendations'
      )
      
      # Budget tracking
      expect(cost_data['budget_tracking']).to include(
        'current_month_spend',
        'projected_month_end',
        'budget_utilization_percent'
      )
    end

    it 'tracks cost per execution trends' do
      get '/api/v1/ai/analytics/cost_per_execution', params: { 
        period: 30,
        group_by: 'day'
      }
      
      expect(response).to have_http_status(:ok)
      trend_data = json_response['data']
      
      expect(trend_data['timeline']).to be_an(Array)
      expect(trend_data['timeline'].first).to include(
        'date',
        'total_cost',
        'total_executions',
        'average_cost_per_execution'
      )
      
      # Verify trend analysis
      expect(trend_data['trend_analysis']).to include(
        'direction',
        'percentage_change',
        'significance'
      )
    end

    it 'provides cost optimization recommendations' do
      get '/api/v1/ai/analytics/cost_optimization'
      
      expect(response).to have_http_status(:ok)
      optimization_data = json_response['data']
      
      expect(optimization_data['recommendations']).to be_an(Array)
      expect(optimization_data['recommendations']).not_to be_empty
      
      # Should include actionable recommendations
      recommendation = optimization_data['recommendations'].first
      expect(recommendation).to include(
        'type',
        'description',
        'potential_savings',
        'implementation_complexity',
        'priority'
      )
      
      # Cost reduction opportunities
      expect(optimization_data['opportunities']).to include(
        'underutilized_agents',
        'expensive_providers',
        'inefficient_configurations'
      )
    end

    it 'tracks budget alerts and thresholds' do
      # Set budget threshold
      post '/api/v1/ai/analytics/budget_thresholds', params: {
        threshold: {
          monthly_budget: 1000.00,
          warning_percentage: 75,
          alert_percentage: 90
        }
      }
      
      expect(response).to have_http_status(:ok)
      
      # Check current budget status
      get '/api/v1/ai/analytics/budget_status'
      
      expect(response).to have_http_status(:ok)
      budget_status = json_response['data']
      
      expect(budget_status).to include(
        'monthly_budget',
        'current_spend',
        'utilization_percentage',
        'days_remaining',
        'projected_end_of_month'
      )
    end
  end

  describe 'Usage Pattern Analysis' do
    before do
      create_usage_pattern_data
    end

    it 'analyzes conversation patterns' do
      get '/api/v1/ai/analytics/conversation_patterns'
      
      expect(response).to have_http_status(:ok)
      pattern_data = json_response['data']
      
      # Conversation metrics
      expect(pattern_data['conversation_metrics']).to include(
        'average_length',
        'peak_hours',
        'common_topics',
        'user_engagement_score'
      )
      
      # Agent utilization patterns
      expect(pattern_data['agent_patterns']).to be_an(Array)
      agent_pattern = pattern_data['agent_patterns'].first
      expect(agent_pattern).to include(
        'agent_name',
        'usage_frequency',
        'success_rate',
        'preferred_hours'
      )
    end

    it 'identifies peak usage times' do
      get '/api/v1/ai/analytics/usage_heatmap', params: { period: 7 }
      
      expect(response).to have_http_status(:ok)
      heatmap_data = json_response['data']
      
      # Hourly breakdown
      expect(heatmap_data['hourly_usage']).to be_an(Array)
      expect(heatmap_data['hourly_usage'].size).to eq(24)
      
      # Daily breakdown
      expect(heatmap_data['daily_usage']).to be_an(Array)
      expect(heatmap_data['daily_usage'].size).to eq(7)
      
      # Peak times identification
      expect(heatmap_data['insights']).to include(
        'peak_hour',
        'peak_day',
        'usage_pattern_type'
      )
    end

    it 'tracks user engagement metrics' do
      get '/api/v1/ai/analytics/user_engagement'
      
      expect(response).to have_http_status(:ok)
      engagement_data = json_response['data']
      
      expect(engagement_data['metrics']).to include(
        'active_users',
        'average_sessions_per_user',
        'average_session_duration',
        'user_retention_rate'
      )
      
      # User segmentation
      expect(engagement_data['user_segments']).to be_an(Array)
      segment = engagement_data['user_segments'].first
      expect(segment).to include(
        'segment_name',
        'user_count',
        'characteristics'
      )
    end
  end

  describe 'Performance Monitoring Integration' do
    it 'integrates with system performance metrics' do
      get '/api/v1/ai/analytics/system_performance'
      
      expect(response).to have_http_status(:ok)
      performance_data = json_response['data']
      
      # System resource usage
      expect(performance_data['system_metrics']).to include(
        'cpu_usage_percent',
        'memory_usage_percent',
        'active_connections',
        'queue_depth'
      )
      
      # AI-specific performance
      expect(performance_data['ai_performance']).to include(
        'average_response_time',
        'concurrent_executions',
        'throughput_per_minute'
      )
    end

    it 'provides health check summaries' do
      get '/api/v1/ai/analytics/health_summary'
      
      expect(response).to have_http_status(:ok)
      health_data = json_response['data']
      
      expect(health_data['overall_status']).to be_in(['healthy', 'warning', 'critical'])
      expect(health_data['component_status']).to be_a(Hash)
      expect(health_data['recent_issues']).to be_an(Array)
    end
  end

  describe 'Export and Reporting' do
    it 'exports analytics data in multiple formats' do
      # JSON export
      get '/api/v1/ai/analytics/export', params: { 
        format: 'json',
        period: 30,
        include: 'summary,timeline,costs'
      }
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      
      export_data = json_response['data']
      expect(export_data).to include('summary', 'timeline', 'costs')
      expect(export_data['metadata']).to include('export_date', 'period', 'account_id')
    end

    it 'generates scheduled reports' do
      # Create scheduled report
      post '/api/v1/ai/analytics/scheduled_reports', params: {
        report: {
          name: 'Weekly AI Summary',
          frequency: 'weekly',
          recipients: [user.email],
          include_sections: ['summary', 'costs', 'performance'],
          format: 'pdf'
        }
      }
      
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      
      # Verify report was created
      expect(json_response['data']['report']).to include(
        'id',
        'name',
        'frequency',
        'next_run_at'
      )
    end

    it 'supports custom analytics queries' do
      post '/api/v1/ai/analytics/custom_query', params: {
        query: {
          metrics: ['total_cost', 'execution_count'],
          dimensions: ['provider', 'agent_type'],
          filters: {
            date_range: { start: 30.days.ago, end: Date.current },
            provider_slugs: ['openai', 'anthropic']
          },
          aggregation: 'sum'
        }
      }
      
      expect(response).to have_http_status(:ok)
      query_results = json_response['data']
      
      expect(query_results['results']).to be_an(Array)
      expect(query_results['metadata']).to include(
        'total_rows',
        'query_time_ms',
        'cache_hit'
      )
    end
  end

  private

  def create_execution_history
    # Create executions across different time periods
    3.times do |i|
      create(:ai_agent_execution, :completed,
             ai_agent: agent1,
             account: account,
             created_at: i.days.ago,
             metadata: { cost: 0.05 + (i * 0.02) })
    end
    
    2.times do |i|
      create(:ai_agent_execution, :completed,
             ai_agent: agent2,
             account: account,
             created_at: i.days.ago,
             metadata: { cost: 0.08 + (i * 0.03) })
    end
    
    # Add some failures
    create(:ai_agent_execution, :failed,
           ai_agent: agent1,
           account: account,
           created_at: 1.day.ago)
  end

  def create_conversation_history
    # Create messages in conversations
    10.times do |i|
      create(:ai_message,
             ai_conversation: conversation1,
             account: account,
             created_at: i.hours.ago,
             sender_type: i.even? ? 'user' : 'ai')
    end
    
    8.times do |i|
      create(:ai_message,
             ai_conversation: conversation2,
             account: account,
             created_at: i.hours.ago,
             sender_type: i.even? ? 'user' : 'ai')
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
        resource_type: 'AiAgentExecution',
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
        resource_type: 'AiAgentExecution',
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
      provider = AiProvider.find_by(slug: provider_slug)
      agent = provider_slug == 'openai' ? agent1 : agent2
      
      # Successful executions
      10.times do |i|
        create(:ai_agent_execution, :completed,
               ai_agent: agent,
               account: account,
               created_at: i.hours.ago,
               metadata: {
                 response_time_ms: 1000 + rand(500),
                 cost: 0.05 + rand(0.03)
               })
      end
      
      # Some failures
      2.times do |i|
        create(:ai_agent_execution, :failed,
               ai_agent: agent,
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
          resource_type: 'AiProvider',
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
                 ai_agent: [agent1, agent2].sample,
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
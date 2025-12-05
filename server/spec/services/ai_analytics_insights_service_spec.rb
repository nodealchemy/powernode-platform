# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAnalyticsInsightsService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, :openai) }
  let(:agent) { create(:ai_agent, account: account, ai_provider: provider) }

  # Create test data with varied execution patterns
  let!(:successful_executions) do
    create_list(:ai_agent_execution, 15, :completed,
                account: account,
                ai_agent: agent,
                tokens_used: 1500,
                estimated_cost: BigDecimal('0.03'),
                response_time_ms: 2000,
                created_at: 1.week.ago)
  end

  let!(:failed_executions) do
    create_list(:ai_agent_execution, 3, :failed,
                account: account,
                ai_agent: agent,
                error_message: 'Rate limit exceeded',
                created_at: 1.week.ago)
  end

  let!(:recent_executions) do
    create_list(:ai_agent_execution, 8, :completed,
                account: account,
                ai_agent: agent,
                tokens_used: 2000,
                estimated_cost: BigDecimal('0.04'),
                response_time_ms: 1800,
                created_at: 1.day.ago)
  end

  describe '#initialize' do
    it 'initializes with account' do
      service = described_class.new(account)
      expect(service.account).to eq(account)
    end

    it 'sets up analytics configurations' do
      service = described_class.new(account)
      expect(service.instance_variable_get(:@analytics_config)).to be_a(Hash)
    end

    it 'initializes metric calculators' do
      service = described_class.new(account)
      expect(service.instance_variable_get(:@metric_calculators)).to be_present
    end
  end

  describe '#usage_analytics' do
    let(:service) { described_class.new(account) }

    context 'for basic usage metrics' do
      it 'returns comprehensive usage analytics' do
        analytics = service.usage_analytics(30.days)
        
        expect(analytics).to include(
          :total_executions,
          :successful_executions,
          :failed_executions,
          :success_rate,
          :total_tokens_used,
          :total_cost,
          :average_cost_per_execution,
          :average_response_time,
          :executions_by_provider,
          :executions_by_agent,
          :daily_usage_trend
        )
      end

      it 'calculates success rate correctly' do
        analytics = service.usage_analytics(30.days)
        
        total = successful_executions.count + failed_executions.count + recent_executions.count
        successful = successful_executions.count + recent_executions.count
        expected_rate = (successful.to_f / total * 100).round(2)
        
        expect(analytics[:success_rate]).to eq(expected_rate)
      end

      it 'aggregates token usage correctly' do
        analytics = service.usage_analytics(30.days)
        
        expected_tokens = (successful_executions.count * 1500) + (recent_executions.count * 2000)
        expect(analytics[:total_tokens_used]).to eq(expected_tokens)
      end

      it 'calculates cost metrics accurately' do
        analytics = service.usage_analytics(30.days)
        
        expected_cost = (successful_executions.count * BigDecimal('0.03')) + 
                       (recent_executions.count * BigDecimal('0.04'))
        
        expect(analytics[:total_cost]).to eq(expected_cost)
        expect(analytics[:average_cost_per_execution]).to be > BigDecimal('0')
      end
    end

    context 'with time period filtering' do
      it 'filters executions by time period correctly' do
        weekly_analytics = service.usage_analytics(7.days)
        monthly_analytics = service.usage_analytics(30.days)
        
        expect(weekly_analytics[:total_executions]).to be < monthly_analytics[:total_executions]
      end

      it 'handles edge cases for time periods' do
        today_analytics = service.usage_analytics(1.day)
        
        expect(today_analytics[:total_executions]).to eq(recent_executions.count)
      end
    end

    context 'with provider breakdown' do
      it 'breaks down usage by provider' do
        analytics = service.usage_analytics(30.days)
        
        provider_breakdown = analytics[:executions_by_provider]
        expect(provider_breakdown).to be_a(Hash)
        expect(provider_breakdown.keys).to include(provider.id)
      end

      it 'includes provider-specific metrics' do
        analytics = service.usage_analytics(30.days)
        
        provider_data = analytics[:executions_by_provider][provider.id]
        expect(provider_data).to include(
          :count,
          :success_rate,
          :average_cost,
          :average_response_time,
          :total_tokens
        )
      end
    end
  end

  describe '#performance_analytics' do
    let(:service) { described_class.new(account) }

    it 'analyzes performance metrics comprehensively' do
      performance = service.performance_analytics(30.days)
      
      expect(performance).to include(
        :response_time_analytics,
        :throughput_analytics,
        :error_analytics,
        :quality_metrics,
        :efficiency_scores,
        :performance_trends
      )
    end

    it 'calculates response time statistics' do
      performance = service.performance_analytics(30.days)
      
      response_time_stats = performance[:response_time_analytics]
      expect(response_time_stats).to include(
        :average,
        :median,
        :p95,
        :p99,
        :min,
        :max,
        :standard_deviation
      )
      
      expect(response_time_stats[:average]).to be > 0
      expect(response_time_stats[:median]).to be > 0
    end

    it 'analyzes throughput patterns' do
      performance = service.performance_analytics(30.days)
      
      throughput = performance[:throughput_analytics]
      expect(throughput).to include(
        :requests_per_hour,
        :peak_throughput,
        :off_peak_throughput,
        :throughput_trend
      )
    end

    it 'provides error analysis' do
      performance = service.performance_analytics(30.days)
      
      error_analysis = performance[:error_analytics]
      expect(error_analysis).to include(
        :error_rate,
        :error_types,
        :error_frequency,
        :mtbf,
        :mttr
      )
      
      expect(error_analysis[:error_types]).to be_a(Hash)
    end

    it 'calculates quality metrics' do
      performance = service.performance_analytics(30.days)
      
      quality = performance[:quality_metrics]
      expect(quality).to include(
        :completion_rate,
        :timeout_rate,
        :retry_rate,
        :quality_score
      )
    end

    it 'generates efficiency scores' do
      performance = service.performance_analytics(30.days)
      
      efficiency = performance[:efficiency_scores]
      expect(efficiency).to include(
        :cost_efficiency,
        :time_efficiency,
        :resource_efficiency,
        :overall_efficiency
      )
      
      efficiency.values.each do |score|
        expect(score).to be >= 0
        expect(score).to be <= 1
      end
    end
  end

  describe '#cost_analytics' do
    let(:service) { described_class.new(account) }

    it 'provides detailed cost analytics' do
      cost_analytics = service.cost_analytics(30.days)
      
      expect(cost_analytics).to include(
        :total_cost,
        :cost_breakdown,
        :cost_trends,
        :cost_per_provider,
        :cost_per_agent,
        :cost_efficiency_metrics,
        :cost_projections
      )
    end

    it 'breaks down costs by multiple dimensions' do
      cost_analytics = service.cost_analytics(30.days)
      
      breakdown = cost_analytics[:cost_breakdown]
      expect(breakdown).to include(
        :by_provider,
        :by_agent,
        :by_day,
        :by_hour
      )
    end

    it 'analyzes cost trends' do
      cost_analytics = service.cost_analytics(30.days)
      
      trends = cost_analytics[:cost_trends]
      expect(trends).to include(
        :daily_trend,
        :weekly_trend,
        :growth_rate,
        :trend_direction
      )
    end

    it 'calculates cost efficiency metrics' do
      cost_analytics = service.cost_analytics(30.days)
      
      efficiency = cost_analytics[:cost_efficiency_metrics]
      expect(efficiency).to include(
        :cost_per_token,
        :cost_per_successful_request,
        :cost_per_minute,
        :roi_score
      )
    end

    it 'provides cost projections' do
      cost_analytics = service.cost_analytics(30.days)
      
      projections = cost_analytics[:cost_projections]
      expect(projections).to include(
        :next_week_projection,
        :next_month_projection,
        :confidence_interval,
        :projected_growth_rate
      )
    end
  end

  describe '#agent_analytics' do
    let(:service) { described_class.new(account) }
    let(:agent2) { create(:ai_agent, account: account, ai_provider: provider) }

    before do
      create_list(:ai_agent_execution, 5, :completed,
                  account: account,
                  ai_agent: agent2,
                  tokens_used: 800,
                  estimated_cost: BigDecimal('0.02'),
                  created_at: 1.day.ago)
    end

    it 'analyzes individual agent performance' do
      agent_analytics = service.agent_analytics(agent.id, 30.days)
      
      expect(agent_analytics).to include(
        :agent_info,
        :execution_summary,
        :performance_metrics,
        :cost_metrics,
        :usage_patterns,
        :optimization_suggestions
      )
    end

    it 'compares agents across the account' do
      comparison = service.agent_comparison(30.days)
      
      expect(comparison).to be_an(Array)
      expect(comparison.size).to be >= 2
      
      agent_data = comparison.first
      expect(agent_data).to include(
        :agent_id,
        :agent_name,
        :total_executions,
        :success_rate,
        :average_cost,
        :performance_rank
      )
    end

    it 'identifies top performing agents' do
      top_agents = service.top_performing_agents(30.days, limit: 5)
      
      expect(top_agents).to be_an(Array)
      expect(top_agents.size).to be <= 5
      
      # Should be sorted by performance score
      scores = top_agents.map { |a| a[:performance_score] }
      expect(scores).to eq(scores.sort.reverse)
    end

    it 'provides agent optimization suggestions' do
      agent_analytics = service.agent_analytics(agent.id, 30.days)
      
      suggestions = agent_analytics[:optimization_suggestions]
      expect(suggestions).to be_an(Array)
      
      if suggestions.any?
        suggestion = suggestions.first
        expect(suggestion).to include(:type, :description, :impact, :effort)
      end
    end
  end

  describe '#generate_insights' do
    let(:service) { described_class.new(account) }

    it 'generates actionable insights from analytics data' do
      insights = service.generate_insights(30.days)
      
      expect(insights).to include(
        :key_insights,
        :performance_insights,
        :cost_insights,
        :usage_insights,
        :recommendations,
        :alerts
      )
    end

    it 'identifies key performance insights' do
      insights = service.generate_insights(30.days)
      
      performance_insights = insights[:performance_insights]
      expect(performance_insights).to be_an(Array)
      
      if performance_insights.any?
        insight = performance_insights.first
        expect(insight).to include(:category, :description, :impact_level, :data_points)
      end
    end

    it 'provides cost optimization insights' do
      insights = service.generate_insights(30.days)
      
      cost_insights = insights[:cost_insights]
      expect(cost_insights).to be_an(Array)
      
      if cost_insights.any?
        cost_insight = cost_insights.first
        expect(cost_insight).to include(:description, :potential_savings, :implementation_complexity)
      end
    end

    it 'generates actionable recommendations' do
      insights = service.generate_insights(30.days)
      
      recommendations = insights[:recommendations]
      expect(recommendations).to be_an(Array)
      
      if recommendations.any?
        rec = recommendations.first
        expect(rec).to include(
          :priority,
          :category,
          :description,
          :expected_impact,
          :implementation_steps
        )
      end
    end

    it 'identifies critical alerts' do
      # Create conditions that should trigger alerts
      create_list(:ai_agent_execution, 5, :failed,
                  account: account,
                  error_message: 'Quota exceeded',
                  created_at: 1.hour.ago)

      insights = service.generate_insights(30.days)
      
      alerts = insights[:alerts]
      expect(alerts).to be_an(Array)
      
      if alerts.any?
        alert = alerts.first
        expect(alert).to include(:severity, :type, :description, :suggested_action)
      end
    end
  end

  describe '#real_time_metrics' do
    let(:service) { described_class.new(account) }

    it 'provides real-time system metrics' do
      metrics = service.real_time_metrics
      
      expect(metrics).to include(
        :current_active_executions,
        :requests_per_minute,
        :average_response_time_5min,
        :error_rate_5min,
        :cost_rate_hourly,
        :system_health_score
      )
    end

    it 'calculates current system load' do
      metrics = service.real_time_metrics
      
      expect(metrics[:current_active_executions]).to be >= 0
      expect(metrics[:requests_per_minute]).to be >= 0
      expect(metrics[:system_health_score]).to be >= 0
      expect(metrics[:system_health_score]).to be <= 1
    end

    it 'tracks short-term performance trends' do
      metrics = service.real_time_metrics
      
      expect(metrics[:average_response_time_5min]).to be >= 0
      expect(metrics[:error_rate_5min]).to be >= 0
      expect(metrics[:error_rate_5min]).to be <= 100
    end
  end

  describe '#export_analytics' do
    let(:service) { described_class.new(account) }

    it 'exports analytics data in multiple formats' do
      csv_export = service.export_analytics(30.days, format: :csv)
      json_export = service.export_analytics(30.days, format: :json)
      
      expect(csv_export).to be_a(String)
      expect(csv_export).to include(',') # CSV format
      
      expect(json_export).to be_a(String)
      expect { JSON.parse(json_export) }.not_to raise_error
    end

    it 'includes comprehensive data in exports' do
      export_data = service.export_analytics(30.days, format: :hash)
      
      expect(export_data).to include(
        :metadata,
        :usage_data,
        :performance_data,
        :cost_data,
        :agent_data
      )
    end

    it 'respects data filtering options' do
      filtered_export = service.export_analytics(
        30.days,
        format: :hash,
        filters: { providers: [provider.id], min_cost: BigDecimal('0.01') }
      )
      
      expect(filtered_export[:usage_data]).to be_present
    end
  end

  describe '#benchmark_comparison' do
    let(:service) { described_class.new(account) }

    it 'compares account performance against benchmarks' do
      comparison = service.benchmark_comparison(30.days)
      
      expect(comparison).to include(
        :performance_vs_benchmark,
        :cost_vs_benchmark,
        :efficiency_vs_benchmark,
        :improvement_areas,
        :strengths
      )
    end

    it 'identifies performance relative to industry standards' do
      comparison = service.benchmark_comparison(30.days)
      
      performance = comparison[:performance_vs_benchmark]
      expect(performance).to include(
        :response_time_percentile,
        :success_rate_percentile,
        :efficiency_percentile
      )
    end

    it 'suggests improvement areas based on benchmarks' do
      comparison = service.benchmark_comparison(30.days)
      
      improvements = comparison[:improvement_areas]
      expect(improvements).to be_an(Array)
      
      if improvements.any?
        improvement = improvements.first
        expect(improvement).to include(:metric, :current_value, :benchmark_value, :gap_analysis)
      end
    end
  end

  describe 'private methods' do
    let(:service) { described_class.new(account) }

    describe '#calculate_percentiles' do
      it 'calculates percentiles correctly' do
        values = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
        
        p50 = service.send(:calculate_percentile, values, 50)
        p95 = service.send(:calculate_percentile, values, 95)
        p99 = service.send(:calculate_percentile, values, 99)
        
        expect(p50).to be_within(50).of(550)
        expect(p95).to be > p50
        expect(p99).to be > p95
      end
    end

    describe '#detect_anomalies' do
      it 'detects statistical anomalies in metrics' do
        normal_values = Array.new(50) { 100 + rand(20) }
        anomaly_values = [100, 500, 50] # Outliers
        
        all_values = normal_values + anomaly_values
        anomalies = service.send(:detect_anomalies, all_values)
        
        expect(anomalies).to be_an(Array)
        expect(anomalies.size).to be > 0
      end
    end

    describe '#calculate_trend' do
      it 'calculates trend direction and magnitude' do
        increasing_values = (1..10).to_a
        decreasing_values = (1..10).to_a.reverse
        
        inc_trend = service.send(:calculate_trend, increasing_values)
        dec_trend = service.send(:calculate_trend, decreasing_values)
        
        expect(inc_trend[:direction]).to eq('increasing')
        expect(dec_trend[:direction]).to eq('decreasing')
        expect(inc_trend[:magnitude]).to be > 0
      end
    end
  end
end
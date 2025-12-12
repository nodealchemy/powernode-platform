# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiCostOptimizationService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Providers with different cost structures
  let(:openai_provider) { create(:ai_provider, :openai, priority_order: 1) }
  let(:anthropic_provider) { create(:ai_provider, :anthropic, priority_order: 2) }
  let(:ollama_provider) { create(:ai_provider, :ollama, priority_order: 3) }

  # Credentials for each provider
  let(:openai_credential) { create(:ai_provider_credential, account: account, ai_provider: openai_provider) }
  let(:anthropic_credential) { create(:ai_provider_credential, account: account, ai_provider: anthropic_provider) }
  let(:ollama_credential) { create(:ai_provider_credential, account: account, ai_provider: ollama_provider) }

  # Historical usage data
  let!(:expensive_execution) do
    create(:ai_agent_execution, :completed,
           account: account,
           tokens_used: 5000,
           cost_usd: BigDecimal('0.15'),
           duration_ms: 2500,
           created_at: 1.day.ago)
  end

  let!(:cheap_execution) do
    create(:ai_agent_execution, :completed,
           account: account,
           tokens_used: 1000,
           cost_usd: BigDecimal('0.002'),
           duration_ms: 3000,
           created_at: 1.day.ago)
  end

  describe '#initialize' do
    it 'initializes with account' do
      service = described_class.new(account: account)
      expect(service.account).to eq(account)
    end

    it 'loads provider cost configurations' do
      service = described_class.new(account: account)
      expect(service.instance_variable_get(:@provider_costs)).to be_a(Hash)
    end

    it 'initializes usage tracking' do
      service = described_class.new(account: account)
      expect(service.instance_variable_get(:@usage_tracker)).to be_present
    end
  end

  describe '#recommend_provider' do
    let(:service) { described_class.new(account: account) }

    before do
      # Set up credentials
      openai_credential
      anthropic_credential
      ollama_credential
    end

    context 'for simple text generation tasks' do
      let(:task_requirements) do
        {
          task_type: 'text_generation',
          complexity: 'simple',
          max_tokens: 100,
          quality_threshold: 0.7,
          budget_priority: 'cost_optimized'
        }
      end

      it 'recommends most cost-effective provider' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation).to include(
          :provider_id,
          :estimated_cost,
          :confidence_score,
          :reasoning,
          :alternative_options
        )
        expect(recommendation[:confidence_score]).to be > 0.5
      end

      it 'prefers local models for cost optimization' do
        recommendation = service.recommend_provider(task_requirements)

        # Should prefer Ollama (local) for cost optimization
        expect(recommendation[:provider_id]).to eq(ollama_provider.id)
        expect(recommendation[:estimated_cost]).to be < BigDecimal('0.01')
      end

      it 'provides detailed reasoning' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation[:reasoning]).to include('cost')
        expect(recommendation[:reasoning]).to be_a(String)
        expect(recommendation[:reasoning].length).to be > 20
      end

      it 'includes alternative options' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation[:alternative_options]).to be_an(Array)
        expect(recommendation[:alternative_options].size).to be >= 1

        alt_option = recommendation[:alternative_options].first
        expect(alt_option).to include(:provider_id, :estimated_cost, :trade_offs)
      end
    end

    context 'for high-quality tasks' do
      let(:task_requirements) do
        {
          task_type: 'text_generation',
          complexity: 'complex',
          max_tokens: 1000,
          quality_threshold: 0.95,
          budget_priority: 'quality_first'
        }
      end

      it 'recommends highest quality provider' do
        recommendation = service.recommend_provider(task_requirements)

        # Should prefer premium providers for quality
        expect([ openai_provider.id, anthropic_provider.id ]).to include(recommendation[:provider_id])
      end

      it 'justifies quality over cost trade-off' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation[:reasoning]).to include('quality')
        expect(recommendation[:estimated_cost]).to be > BigDecimal('0.01')
      end
    end

    context 'for balanced optimization' do
      let(:task_requirements) do
        {
          task_type: 'text_generation',
          complexity: 'medium',
          max_tokens: 500,
          quality_threshold: 0.8,
          budget_priority: 'balanced'
        }
      end

      it 'balances cost and quality factors' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation[:confidence_score]).to be > 0.5
        expect(recommendation[:estimated_cost]).to be > BigDecimal('0.001')
        expect(recommendation[:estimated_cost]).to be < BigDecimal('10.0')
      end

      it 'considers response time requirements' do
        fast_requirements = task_requirements.merge(max_response_time_ms: 1000)
        recommendation = service.recommend_provider(fast_requirements)

        expect(recommendation[:estimated_response_time_ms]).to be <= 1500
      end
    end

    context 'with budget constraints' do
      let(:task_requirements) do
        {
          task_type: 'text_generation',
          complexity: 'simple',
          max_tokens: 200,
          max_cost: BigDecimal('0.005')
        }
      end

      it 'respects hard budget limits' do
        recommendation = service.recommend_provider(task_requirements)

        expect(recommendation[:estimated_cost]).to be <= BigDecimal('0.005')
      end

      it 'warns when budget is insufficient' do
        impossible_requirements = task_requirements.merge(
          complexity: 'complex',
          max_tokens: 5000,
          max_cost: BigDecimal('0.001')
        )

        recommendation = service.recommend_provider(impossible_requirements)

        expect(recommendation[:warnings]).to include(/budget.*insufficient/i)
      end
    end
  end

  describe '#analyze_usage_patterns' do
    let(:service) { described_class.new(account: account) }

    before do
      # Create varied execution history
      create_list(:ai_agent_execution, 10, :completed,
                  account: account,
                  tokens_used: 1500,
                  cost_usd: BigDecimal('0.03'),
                  created_at: 1.week.ago)

      create_list(:ai_agent_execution, 5, :completed,
                  account: account,
                  tokens_used: 500,
                  cost_usd: BigDecimal('0.01'),
                  created_at: 3.days.ago)
    end

    it 'analyzes spending patterns over time' do
      analysis = service.analyze_usage_patterns(30.days)

      expect(analysis).to include(
        :total_cost,
        :total_tokens,
        :average_cost_per_token,
        :usage_trend,
        :cost_breakdown_by_provider,
        :optimization_opportunities
      )
    end

    it 'identifies cost trends' do
      analysis = service.analyze_usage_patterns(30.days)

      expect(analysis[:usage_trend]).to be_in([ 'increasing', 'decreasing', 'stable' ])
      expect(analysis[:total_cost]).to be > BigDecimal('0')
    end

    it 'breaks down costs by provider' do
      analysis = service.analyze_usage_patterns(30.days)

      expect(analysis[:cost_breakdown_by_provider]).to be_a(Hash)
      expect(analysis[:cost_breakdown_by_provider].keys).to all(be_a(String))
      expect(analysis[:cost_breakdown_by_provider].values).to all(be_a(BigDecimal))
    end

    it 'suggests optimization opportunities' do
      analysis = service.analyze_usage_patterns(30.days)

      expect(analysis[:optimization_opportunities]).to be_an(Array)

      if analysis[:optimization_opportunities].any?
        opportunity = analysis[:optimization_opportunities].first
        expect(opportunity).to include(:type, :description, :potential_savings)
      end
    end

    it 'calculates efficiency metrics' do
      analysis = service.analyze_usage_patterns(30.days)

      expect(analysis[:efficiency_metrics]).to include(
        :tokens_per_dollar,
        :average_response_time,
        :success_rate,
        :cost_efficiency_score
      )
    end
  end

  describe '#optimize_provider_selection' do
    let(:service) { described_class.new(account: account) }

    before do
      openai_credential
      anthropic_credential
      ollama_credential
    end

    it 'optimizes provider mix for workload' do
      workload_profile = {
        simple_tasks: 60,
        medium_tasks: 30,
        complex_tasks: 10,
        monthly_budget: BigDecimal('100.00')
      }

      optimization = service.optimize_provider_selection(workload_profile)

      expect(optimization).to include(
        :recommended_mix,
        :projected_cost,
        :projected_savings,
        :risk_assessment
      )
    end

    it 'suggests optimal provider mix percentages' do
      workload_profile = {
        simple_tasks: 80,
        medium_tasks: 15,
        complex_tasks: 5,
        monthly_budget: BigDecimal('50.00')
      }

      optimization = service.optimize_provider_selection(workload_profile)

      mix = optimization[:recommended_mix]
      expect(mix).to be_a(Hash)
      expect(mix.values.sum).to be_within(0.01).of(1.0) # Should sum to 100%
    end

    it 'projects cost savings from optimization' do
      workload_profile = {
        simple_tasks: 70,
        medium_tasks: 25,
        complex_tasks: 5,
        monthly_budget: BigDecimal('75.00')
      }

      optimization = service.optimize_provider_selection(workload_profile)

      expect(optimization[:projected_savings]).to be >= BigDecimal('0')
      expect(optimization[:projected_cost]).to be <= workload_profile[:monthly_budget]
    end

    it 'assesses risks of optimization strategy' do
      workload_profile = {
        simple_tasks: 100,
        medium_tasks: 0,
        complex_tasks: 0,
        monthly_budget: BigDecimal('10.00')
      }

      optimization = service.optimize_provider_selection(workload_profile)

      expect(optimization[:risk_assessment]).to include(
        :quality_risk,
        :availability_risk,
        :vendor_lock_in_risk
      )
    end
  end

  describe '#budget_monitoring' do
    let(:service) { described_class.new(account: account) }

    before do
      # Set up budget tracking via settings
      account.update!(settings: (account.settings || {}).merge('monthly_ai_budget' => '100.00'))
    end

    it 'tracks current month spending' do
      status = service.budget_status(Date.current.beginning_of_month, Date.current.end_of_month)

      expect(status).to include(
        :budget_limit,
        :current_spending,
        :remaining_budget,
        :projected_monthly_cost,
        :budget_utilization_percent
      )
    end

    it 'calculates budget utilization percentage' do
      status = service.budget_status(Date.current.beginning_of_month, Date.current.end_of_month)

      expect(status[:budget_utilization_percent]).to be >= 0
      expect(status[:budget_utilization_percent]).to be <= 100
    end

    it 'projects end-of-month spending' do
      status = service.budget_status(Date.current.beginning_of_month, Date.current.end_of_month)

      expect(status[:projected_monthly_cost]).to be_a(BigDecimal)
      expect(status[:projected_monthly_cost]).to be >= status[:current_spending]
    end

    it 'provides budget alerts when approaching limits' do
      # Simulate high spending
      create_list(:ai_agent_execution, 20, :completed,
                  account: account,
                  cost_usd: BigDecimal('4.00'),
                  created_at: 2.days.ago)

      status = service.budget_status(Date.current.beginning_of_month, Date.current.end_of_month)

      if status[:budget_utilization_percent] > 80
        expect(status[:alerts]).to be_present
        expect(status[:alerts]).to include(/budget/i)
      end
    end
  end

  describe '#cost_comparison' do
    let(:service) { described_class.new(account: account) }

    it 'compares costs across providers for given requirements' do
      requirements = {
        task_type: 'text_generation',
        estimated_tokens: 1000,
        monthly_volume: 10000
      }

      comparison = service.cost_comparison(requirements)

      expect(comparison).to be_an(Array)
      expect(comparison.size).to be >= 2

      provider_comparison = comparison.first
      expect(provider_comparison).to include(
        :provider_name,
        :cost_per_request,
        :monthly_cost,
        :cost_rank,
        :value_score
      )
    end

    it 'ranks providers by cost effectiveness' do
      requirements = {
        task_type: 'text_generation',
        estimated_tokens: 500,
        monthly_volume: 5000
      }

      comparison = service.cost_comparison(requirements)
      costs = comparison.map { |p| p[:monthly_cost] }

      # Should be sorted by cost (ascending)
      expect(costs).to eq(costs.sort)
    end

    it 'calculates value scores considering quality and cost' do
      requirements = {
        task_type: 'text_generation',
        estimated_tokens: 1500,
        monthly_volume: 8000,
        quality_weight: 0.7,
        cost_weight: 0.3
      }

      comparison = service.cost_comparison(requirements)

      comparison.each do |provider|
        expect(provider[:value_score]).to be >= 0
        expect(provider[:value_score]).to be <= 1
      end
    end
  end

  describe '#generate_cost_report' do
    let(:service) { described_class.new(account: account) }

    before do
      create_list(:ai_agent_execution, 15, :completed,
                  account: account,
                  cost_usd: BigDecimal('0.05'),
                  created_at: 2.weeks.ago)
    end

    it 'generates comprehensive cost report' do
      report = service.generate_cost_report(30.days)

      expect(report).to include(
        :executive_summary,
        :detailed_breakdown,
        :trends_analysis,
        :optimization_recommendations,
        :forecast
      )
    end

    it 'includes executive summary with key metrics' do
      report = service.generate_cost_report(30.days)

      summary = report[:executive_summary]
      expect(summary).to include(
        :total_cost,
        :total_requests,
        :average_cost_per_request,
        :cost_change_percentage,
        :top_cost_driver
      )
    end

    it 'provides actionable optimization recommendations' do
      report = service.generate_cost_report(30.days)

      recommendations = report[:optimization_recommendations]
      expect(recommendations).to be_an(Array)

      if recommendations.any?
        rec = recommendations.first
        expect(rec).to include(:priority, :description, :estimated_savings, :implementation_effort)
      end
    end

    it 'forecasts future costs based on trends' do
      report = service.generate_cost_report(30.days)

      forecast = report[:forecast]
      expect(forecast).to include(
        :next_month_projected_cost,
        :confidence_interval,
        :key_assumptions
      )
    end
  end

  describe '#real_time_cost_tracking' do
    let(:service) { described_class.new(account: account) }

    it 'tracks costs in real-time during execution' do
      execution_context = {
        provider_id: openai_provider.id,
        estimated_tokens: 1000,
        complexity: 'medium'
      }

      tracker = service.start_cost_tracking(execution_context)

      expect(tracker).to include(
        :tracking_id,
        :estimated_cost,
        :start_time,
        :budget_impact
      )
    end

    it 'updates costs as execution progresses' do
      tracker = service.start_cost_tracking(provider_id: openai_provider.id)

      update_result = service.update_cost_tracking(tracker[:tracking_id], {
        actual_tokens: 1200,
        response_time_ms: 2500
      })

      expect(update_result[:actual_cost]).to be > tracker[:estimated_cost]
    end

    it 'provides budget alerts during expensive operations' do
      # Set low budget via settings
      account.update!(settings: (account.settings || {}).merge('monthly_ai_budget' => '1.00'))

      expensive_context = {
        provider_id: openai_provider.id,
        estimated_tokens: 10000,
        complexity: 'complex'
      }

      tracker = service.start_cost_tracking(expensive_context)

      if tracker[:estimated_cost] > BigDecimal('0.50')
        expect(tracker[:budget_alerts]).to be_present
      end
    end
  end

  describe 'private methods' do
    let(:service) { described_class.new(account: account) }

    describe '#calculate_provider_value_score' do
      it 'calculates balanced value scores' do
        provider_metrics = {
          cost_per_token: BigDecimal('0.0001'),
          quality_score: 0.85,
          response_time_ms: 2000,
          reliability_score: 0.95
        }

        weights = { cost: 0.4, quality: 0.3, speed: 0.2, reliability: 0.1 }

        score = service.send(:calculate_provider_value_score, provider_metrics, weights)

        expect(score).to be >= 0
        expect(score).to be <= 1
      end
    end

    describe '#estimate_monthly_cost' do
      it 'projects monthly costs from usage patterns' do
        daily_usage = {
          requests: 100,
          average_tokens: 1500,
          average_cost: BigDecimal('0.03')
        }

        monthly_estimate = service.send(:estimate_monthly_cost, daily_usage)

        expect(monthly_estimate).to be_a(BigDecimal)
        expect(monthly_estimate).to be > BigDecimal('0')
      end
    end
  end
end

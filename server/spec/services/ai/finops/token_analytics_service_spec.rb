# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Finops::TokenAnalyticsService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  # Create a provider for metrics
  let(:provider) { create(:ai_provider, account: account) }

  describe '#usage_summary' do
    context 'with no data' do
      it 'returns zero values' do
        result = service.usage_summary(period: 30.days)

        expect(result[:total_tokens]).to eq(0)
        expect(result[:prompt_tokens]).to eq(0)
        expect(result[:completion_tokens]).to eq(0)
        expect(result[:total_cost]).to eq(0)
        expect(result[:period_days]).to eq(30)
      end
    end

    context 'with provider metrics' do
      before do
        create(:ai_provider_metric,
          account: account,
          provider: provider,
          total_tokens: 5000,
          total_input_tokens: 3000,
          total_output_tokens: 2000,
          total_cost_usd: 0.05,
          recorded_at: 1.day.ago,
          granularity: "day"
        )
      end

      it 'returns aggregate token usage' do
        result = service.usage_summary(period: 30.days)

        expect(result[:total_tokens]).to eq(5000)
        expect(result[:prompt_tokens]).to eq(3000)
        expect(result[:completion_tokens]).to eq(2000)
        expect(result[:total_cost]).to eq(0.05)
      end

      it 'calculates average cost per 1k tokens' do
        result = service.usage_summary(period: 30.days)

        expected = (0.05 / (5000 / 1000.0)).round(6)
        expect(result[:avg_cost_per_1k_tokens]).to eq(expected)
      end

      it 'includes by_tier breakdown' do
        result = service.usage_summary(period: 30.days)

        expect(result[:by_tier]).to be_an(Array)
        expect(result[:by_tier].map { |t| t[:tier] }).to include("economy", "standard", "premium")
      end
    end
  end

  describe '#waste_analysis' do
    context 'with no data' do
      it 'returns zero waste metrics' do
        result = service.waste_analysis

        expect(result[:redundant_context_ratio]).to be_a(Numeric)
        expect(result[:cache_miss_rate]).to be_a(Numeric)
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    context 'with routing decisions' do
      before do
        # Create routing decisions with varying cache/compression states
        5.times do
          create(:ai_routing_decision,
            account: account,
            was_cached: true,
            was_compressed: false,
            estimated_tokens: 2000,
            cached_tokens: 1000
          )
        end
        5.times do
          create(:ai_routing_decision,
            account: account,
            was_cached: false,
            was_compressed: false,
            estimated_tokens: 3000,
            cached_tokens: 0
          )
        end
      end

      it 'calculates cache usage rate' do
        result = service.waste_analysis

        expect(result[:cache_usage_rate]).to eq(50.0)
      end

      it 'generates recommendations for uncached large requests' do
        result = service.waste_analysis

        cache_recs = result[:recommendations].select { |r| r[:type] == "caching" }
        expect(cache_recs).not_to be_empty
      end
    end
  end

  describe '#forecast' do
    context 'with insufficient data' do
      it 'returns insufficient data response' do
        result = service.forecast(months: 3)

        expect(result[:based_on_days]).to eq(0)
        expect(result[:projections]).to be_empty
        expect(result[:message]).to include("Insufficient data")
      end
    end

    context 'with sufficient daily data' do
      before do
        # Create 14 days of daily metrics
        14.times do |i|
          create(:ai_provider_metric,
            account: account,
            provider: provider,
            granularity: "day",
            recorded_at: (14 - i).days.ago,
            total_tokens: 1000 + (i * 100),
            total_cost_usd: 0.01 + (i * 0.001)
          )
        end
      end

      it 'returns projections for requested months' do
        result = service.forecast(months: 3)

        expect(result[:projections].length).to eq(3)
        expect(result[:projections].first[:month]).to eq(1)
        expect(result[:projections].last[:month]).to eq(3)
      end

      it 'applies deflation factor' do
        result = service.forecast(months: 3)

        expect(result[:deflation_factor]).to eq(0.95)
        result[:projections].each do |projection|
          expect(projection[:deflation_applied]).to be <= 1.0
        end
      end

      it 'includes trend data' do
        result = service.forecast(months: 3)

        expect(result[:avg_daily_tokens]).to be > 0
        expect(result[:avg_daily_cost]).to be > 0
        expect(result[:based_on_days]).to be >= 7
      end

      it 'includes confidence levels' do
        result = service.forecast(months: 3)

        confidences = result[:projections].map { |p| p[:confidence] }
        expect(confidences.first).to eq("high")
        expect(confidences.last).to eq("low")
      end
    end
  end

  describe '#optimization_score' do
    context 'with no data' do
      it 'returns a default score' do
        result = service.optimization_score

        expect(result[:score]).to be_a(Numeric)
        expect(result[:score]).to be_between(0, 100)
        expect(result[:grade]).to be_present
        expect(result[:breakdown]).to be_a(Hash)
      end
    end

    it 'includes all four score components' do
      result = service.optimization_score

      expect(result[:breakdown]).to have_key(:cache_hit_rate)
      expect(result[:breakdown]).to have_key(:tier_utilization)
      expect(result[:breakdown]).to have_key(:waste_ratio)
      expect(result[:breakdown]).to have_key(:budget_efficiency)
    end

    it 'includes recommendations' do
      result = service.optimization_score

      expect(result[:recommendations]).to be_an(Array)
    end

    it 'assigns correct grades' do
      result = service.optimization_score

      score = result[:score]
      expected_grade = case score
                       when 90..100 then "A"
                       when 80..89 then "B"
                       when 70..79 then "C"
                       when 60..69 then "D"
                       else "F"
                       end
      expect(result[:grade]).to eq(expected_grade)
    end
  end
end

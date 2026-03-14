# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::Evaluators::Concerns::DynamicKelly do
  let(:test_class) do
    Class.new(Trading::Evaluators::Base) do
      include Trading::Evaluators::Concerns::DynamicKelly
    end
  end

  let(:base_context) do
    {
      "strategy" => { "id" => "s1", "pair" => "BTC-YES", "parameters" => params },
      "market_data" => { "last_price" => 0.50, "bid" => 0.49, "ask" => 0.51, "volume_24h" => 500_000 },
      "positions" => [],
      "allocated_capital" => 1000.0,
      "performance_context" => performance_context
    }
  end

  let(:params) { {} }
  let(:performance_context) { {} }
  let(:evaluator) { test_class.new(base_context) }

  describe "#dynamic_kelly" do
    context "with no historical data" do
      it "returns edge-only Kelly" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.60, market_price: 0.50)
        expect(result[:blend_source]).to eq("edge_only")
        expect(result[:kelly_fraction]).to be > 0
        expect(result[:kelly_fraction]).to be <= 0.15 # max cap
      end

      it "returns zero Kelly when no edge" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.50, market_price: 0.50)
        expect(result[:kelly_fraction]).to eq(0.0)
        expect(result[:kelly_full]).to eq(0.0)
      end
    end

    context "with insufficient historical data (< 10 trades)" do
      let(:performance_context) do
        {
          "edge_profile" => { "valid" => true, "total_trades" => 5, "win_rate" => 0.60 },
          "optimal_kelly" => 0.20
        }
      end

      it "uses edge-only despite historical data existing" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.65, market_price: 0.50)
        expect(result[:blend_source]).to eq("edge_only_insufficient_history")
        expect(result[:total_trades]).to eq(5)
      end
    end

    context "with moderate historical data (10-100 trades)" do
      let(:performance_context) do
        {
          "edge_profile" => { "valid" => true, "total_trades" => 50, "win_rate" => 0.55 },
          "optimal_kelly" => 0.12
        }
      end

      it "blends edge and historical Kelly" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.65, market_price: 0.50)
        expect(result[:blend_source]).to eq("blended")
        expect(result[:kelly_fraction]).to be > 0
      end
    end

    context "with extensive historical data (100+ trades)" do
      let(:performance_context) do
        {
          "edge_profile" => { "valid" => true, "total_trades" => 200, "win_rate" => 0.58 },
          "optimal_kelly" => 0.10
        }
      end

      it "weights heavily toward historical Kelly" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.65, market_price: 0.50)
        expect(result[:blend_source]).to eq("historical_dominant")
      end
    end

    context "with large edge" do
      it "still respects max cap" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.90, market_price: 0.50)
        expect(result[:kelly_fraction]).to be <= 0.15
      end
    end

    context "with custom safety params" do
      let(:params) { { "kelly_safety_multiplier" => 0.5, "max_kelly_fraction" => 0.10 } }

      it "applies custom safety multiplier and cap" do
        result = evaluator.dynamic_kelly(estimated_prob: 0.70, market_price: 0.50)
        expect(result[:kelly_fraction]).to be <= 0.10
        expect(result[:safety_multiplier]).to eq(0.5)
      end
    end

    it "adjusts for price impact" do
      result = evaluator.dynamic_kelly(estimated_prob: 0.60, market_price: 0.50)
      expect(result[:edge_after_impact]).to be >= 0
      expect(result[:edge_after_impact]).to be <= 0.10
    end

    it "handles short direction correctly" do
      result = evaluator.dynamic_kelly(estimated_prob: 0.40, market_price: 0.50)
      expect(result[:kelly_fraction]).to be > 0
      expect(result[:kelly_full]).to be > 0
    end
  end
end

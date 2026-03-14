# frozen_string_literal: true

require "spec_helper"

RSpec.describe Trading::Evaluators::Concerns::DepthAware do
  let(:test_class) do
    Class.new(Trading::Evaluators::Base)
  end

  let(:base_context) do
    {
      "strategy" => { "id" => "s1", "pair" => "BTC-YES", "parameters" => {} },
      "market_data" => { "last_price" => 0.55, "bid" => 0.53, "ask" => 0.57, "volume_24h" => 50_000 },
      "positions" => [],
      "allocated_capital" => 1000.0,
      "order_book" => order_book
    }
  end

  let(:order_book) { {} }
  let(:evaluator) { test_class.new(base_context) }

  describe "#estimate_price_impact" do
    context "with a populated order book" do
      let(:order_book) do
        {
          "bids" => [
            { "price" => 0.54, "quantity" => 100 },
            { "price" => 0.53, "quantity" => 200 },
            { "price" => 0.52, "quantity" => 500 }
          ],
          "asks" => [
            { "price" => 0.56, "quantity" => 100 },
            { "price" => 0.57, "quantity" => 200 },
            { "price" => 0.58, "quantity" => 500 }
          ]
        }
      end

      it "walks buy side levels for small orders" do
        result = evaluator.estimate_price_impact(side: "buy", size_usd: 50.0)
        expect(result[:effective_price]).to be_within(0.01).of(0.56)
        expect(result[:slippage_pct]).to be >= 0
        expect(result[:levels_consumed]).to eq(1)
      end

      it "walks multiple levels for larger orders" do
        # First level: 100 contracts * $0.56 = $56 capacity
        # Second level: 200 contracts * $0.57 = $114 capacity
        result = evaluator.estimate_price_impact(side: "buy", size_usd: 150.0)
        expect(result[:levels_consumed]).to be >= 2
        expect(result[:effective_price]).to be > 0.56
      end

      it "walks sell side levels" do
        result = evaluator.estimate_price_impact(side: "sell", size_usd: 50.0)
        expect(result[:effective_price]).to be_within(0.01).of(0.54)
        expect(result[:levels_consumed]).to eq(1)
      end
    end

    context "with an empty order book" do
      let(:order_book) { { "bids" => [], "asks" => [] } }

      it "falls back to LMSR or spread-based estimate" do
        result = evaluator.estimate_price_impact(side: "buy", size_usd: 50.0)
        expect(result[:levels_consumed]).to eq(0)
        expect(result[:slippage_pct]).to be >= 0
      end
    end
  end

  describe "#lmsr_effective_b" do
    it "returns higher b for tighter spreads" do
      tight = evaluator.send(:lmsr_effective_b, spread: 0.02, volume_24h: 50_000)
      wide = evaluator.send(:lmsr_effective_b, spread: 0.10, volume_24h: 50_000)
      expect(tight).to be > wide
    end

    it "returns higher b for higher volume" do
      high_vol = evaluator.send(:lmsr_effective_b, spread: 0.04, volume_24h: 100_000)
      low_vol = evaluator.send(:lmsr_effective_b, spread: 0.04, volume_24h: 100)
      expect(high_vol).to be > low_vol
    end

    it "clamps within reasonable range" do
      result = evaluator.send(:lmsr_effective_b, spread: 0.0001, volume_24h: 1_000_000)
      expect(result).to be <= 10_000.0
      expect(result).to be >= 1.0
    end
  end

  describe "#lmsr_price_impact" do
    it "returns higher slippage for larger orders" do
      small = evaluator.send(:lmsr_price_impact, size_usd: 10.0, current_price: 0.50, b: 50.0)
      large = evaluator.send(:lmsr_price_impact, size_usd: 500.0, current_price: 0.50, b: 50.0)
      expect(large).to be > small
    end

    it "returns lower slippage for higher b (deeper markets)" do
      shallow = evaluator.send(:lmsr_price_impact, size_usd: 10.0, current_price: 0.50, b: 10.0)
      deep = evaluator.send(:lmsr_price_impact, size_usd: 10.0, current_price: 0.50, b: 100.0)
      expect(deep).to be < shallow
    end

    it "clamps at 0.5 maximum" do
      result = evaluator.send(:lmsr_price_impact, size_usd: 100_000.0, current_price: 0.50, b: 1.0)
      expect(result).to be <= 0.5
    end
  end

  describe "#estimate_signal_cost" do
    context "with order book data" do
      let(:order_book) do
        {
          "bids" => [{ "price" => 0.54, "quantity" => 500 }],
          "asks" => [{ "price" => 0.56, "quantity" => 500 }]
        }
      end

      it "uses book walk for cost estimation" do
        cost = evaluator.estimate_signal_cost
        expect(cost).to be_between(0.0, 0.08)
        expect(cost).to be > 0
      end
    end

    context "without order book but with spread and volume" do
      let(:order_book) { {} }

      it "falls back to LMSR estimation" do
        cost = evaluator.estimate_signal_cost
        expect(cost).to be_between(0.0, 0.08)
      end
    end

    context "with no market data" do
      let(:base_context) do
        {
          "strategy" => { "id" => "s1", "pair" => "X", "parameters" => {} },
          "market_data" => { "last_price" => 0.50 },
          "positions" => [],
          "allocated_capital" => 100.0
        }
      end

      it "falls back to default spread cost" do
        cost = evaluator.estimate_signal_cost
        expect(cost).to eq(0.01) # 0.005 * 2
      end
    end

    it "caps at 8%" do
      cost = evaluator.estimate_signal_cost
      expect(cost).to be <= 0.08
    end
  end
end

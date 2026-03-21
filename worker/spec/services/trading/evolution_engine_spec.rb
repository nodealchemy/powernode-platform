# frozen_string_literal: true

require "rails_helper"

RSpec.describe Trading::EvolutionEngine do
  let(:data_fetcher) { instance_double(Trading::DataFetcher) }
  let(:engine) { described_class.new(data_fetcher) }
  let(:portfolio_id) { "portfolio-uuid-123" }
  let(:epoch_id) { "epoch-uuid-456" }

  let(:strategy_with_metrics) do
    {
      "id" => "strat-1",
      "name" => "LLM Prob Alpha",
      "strategy_type" => "llm_probability",
      "pair" => "KL_WEATHER/YES",
      "status" => "active",
      "allocated_capital_usd" => 100.0,
      "venue_slug" => "kalshi",
      "trading_venue_id" => "venue-1",
      "version_id" => "version-1",
      "parameters" => { "edge_threshold_pct" => 5.0, "temperature" => 0.3 },
      "tick_interval_seconds" => 300,
      "risk_tier" => "medium",
      "recent_candidate_scores" => [0.45, 0.52, 0.38],
      "days_since_creation" => 5.0,
      "budget_spent_cents" => 500,
      "config_avg_tick_cost_usd" => 0.02,
      "config_llm_tick_count" => 25,
      "metrics" => {
        "sharpe_ratio" => 1.8,
        "sortino_ratio" => 2.1,
        "max_drawdown_pct" => 3.5,
        "win_rate" => 0.65,
        "profit_factor" => 2.0,
        "pnl_usd" => 15.0
      },
      "daily_return_count" => 7
    }
  end

  let(:strategy_without_metrics) do
    {
      "id" => "strat-2",
      "name" => "Sentiment Beta",
      "strategy_type" => "sentiment_analysis",
      "pair" => "KL_POLITICS/YES",
      "status" => "active",
      "allocated_capital_usd" => 50.0,
      "venue_slug" => "kalshi",
      "trading_venue_id" => "venue-1",
      "version_id" => "version-2",
      "parameters" => { "sentiment_shift_threshold" => 0.3 },
      "tick_interval_seconds" => 300,
      "risk_tier" => "medium",
      "recent_candidate_scores" => [],
      "days_since_creation" => 0.5,
      "budget_spent_cents" => 0,
      "config_avg_tick_cost_usd" => 0.0,
      "config_llm_tick_count" => 0,
      "metrics" => nil,
      "open_position_count" => 2,
      "unrealized_pnl_usd" => 3.0,
      "has_positions" => true,
      "has_open_positions" => true,
      "position_count" => 2
    }
  end

  let(:regimes) do
    {
      "KL_WEATHER/YES" => { "trend" => "sideways", "volatility" => "calm", "attention" => "normal", "efficiency" => "normal" },
      "KL_POLITICS/YES" => { "trend" => "trending_up", "volatility" => "volatile", "attention" => "high", "efficiency" => "inefficient" }
    }
  end

  let(:portfolio_config) do
    {
      "decommission_threshold" => 0.1,
      "decommission_consecutive_epochs" => 3,
      "use_portfolio_optimizer" => false,
      "optimizer_config" => {},
      "available_capital_usd" => 50.0,
      "epoch_number" => 5
    }
  end

  let(:create_epoch_response) do
    {
      "epoch_id" => epoch_id,
      "epoch_number" => 5,
      "strategies" => [strategy_with_metrics, strategy_without_metrics],
      "regimes" => regimes,
      "portfolio_config" => portfolio_config
    }
  end

  let(:apply_result) do
    {
      "candidates_created" => 2,
      "bred_strategy_id" => "child-strat-1",
      "bred_strategy_name" => "LLM Prob Alpha x Sentiment Beta (gen5)"
    }
  end

  describe "#run_epoch!" do
    before do
      allow(data_fetcher).to receive(:evolution_create_epoch).and_return(create_epoch_response)
      allow(data_fetcher).to receive(:evolution_apply_actions).and_return(apply_result)
      allow(data_fetcher).to receive(:evolution_complete_epoch).and_return({ "epoch_id" => epoch_id, "status" => "completed" })
    end

    it "runs a complete evolution epoch" do
      result = engine.run_epoch!(portfolio_id)

      expect(result[:epoch_id]).to eq(epoch_id)
      expect(result[:strategies_evaluated]).to eq(2)
      expect(result[:bred_strategy]).to eq("LLM Prob Alpha x Sentiment Beta (gen5)")
    end

    it "calls data fetcher endpoints in order" do
      engine.run_epoch!(portfolio_id)

      expect(data_fetcher).to have_received(:evolution_create_epoch)
        .with(portfolio_id: portfolio_id, trigger_type: "scheduled")
      expect(data_fetcher).to have_received(:evolution_apply_actions)
      expect(data_fetcher).to have_received(:evolution_complete_epoch)
    end

    it "passes trigger_type to create_epoch" do
      engine.run_epoch!(portfolio_id, trigger_type: "manual")

      expect(data_fetcher).to have_received(:evolution_create_epoch)
        .with(portfolio_id: portfolio_id, trigger_type: "manual")
    end

    context "when no eligible strategies" do
      before do
        allow(data_fetcher).to receive(:evolution_create_epoch)
          .and_return({ "skipped" => true, "reason" => "no_eligible_strategies" })
      end

      it "returns skipped result" do
        result = engine.run_epoch!(portfolio_id)

        expect(result[:skipped]).to be true
        expect(data_fetcher).not_to have_received(:evolution_apply_actions)
      end
    end

    context "when epoch fails" do
      before do
        allow(data_fetcher).to receive(:evolution_apply_actions)
          .and_raise(StandardError, "API timeout")
      end

      it "calls complete_epoch with error and re-raises" do
        expect { engine.run_epoch!(portfolio_id) }.to raise_error(StandardError, "API timeout")

        expect(data_fetcher).to have_received(:evolution_complete_epoch)
          .with(epoch_id: epoch_id, error: "API timeout")
      end
    end

    it "ranks strategies by fitness (higher = better rank)" do
      engine.run_epoch!(portfolio_id)

      candidates_arg = nil
      expect(data_fetcher).to have_received(:evolution_apply_actions) do |args|
        candidates_arg = args[:candidates]
      end

      # Strategy with real metrics should rank higher than fallback
      ranked_ids = candidates_arg.map { |c| c[:strategy_id] }
      expect(ranked_ids.first).to eq("strat-1")
    end

    it "includes breed request for top 2 strategies" do
      engine.run_epoch!(portfolio_id)

      expect(data_fetcher).to have_received(:evolution_apply_actions) do |args|
        expect(args[:breed_request]).to be_present
        expect(args[:breed_request][:parent_a_id]).to eq("strat-1")
        expect(args[:breed_request][:parent_b_id]).to eq("strat-2")
        expect(args[:breed_request][:strategy_type]).to eq("llm_probability")
      end
    end
  end

  describe "scoring" do
    it "computes metric-based fitness in (0, 1) range" do
      scored = engine.send(:score_strategies, [strategy_with_metrics], regimes)

      expect(scored.first[:fitness_score]).to be_between(0.0, 1.0)
      expect(scored.first[:fitness_score]).to be > 0.3 # Good metrics should score well
    end

    it "computes fallback fitness for strategies without metrics" do
      scored = engine.send(:score_strategies, [strategy_without_metrics], regimes)

      expect(scored.first[:fitness_score]).to be_between(0.0, 0.20)
      expect(scored.first[:fitness_breakdown][:using_fallback]).to be true
    end

    it "applies regime adjustment" do
      # Test that regime adjustment works
      base = 0.6
      regime = { "trend" => "sideways", "volatility" => "calm" }

      adjusted = engine.send(:regime_adjusted_fitness, "llm_probability", base, regime)
      expect(adjusted).to be_between(0.0, 1.0)
    end

    it "gives minimum data-point guard neutral Sharpe for few data points" do
      strategy = strategy_with_metrics.merge("daily_return_count" => 3)
      scored = engine.send(:score_strategies, [strategy], regimes)

      # With < 5 data points, Sharpe component uses neutral 0.5 instead of computed value
      expect(scored.first[:fitness_score]).to be_between(0.0, 1.0)
    end

    it "caps fallback fitness at 0.20" do
      # Strategy with lots of open positions but no metrics
      rich_fallback = strategy_without_metrics.merge(
        "allocated_capital_usd" => 1000.0,
        "open_position_count" => 10,
        "unrealized_pnl_usd" => 50.0,
        "position_count" => 10,
        "days_since_creation" => 0.1
      )
      scored = engine.send(:score_strategies, [rich_fallback], regimes)
      expect(scored.first[:fitness_score]).to be <= 0.20
    end
  end

  describe "capital allocation" do
    it "allocates fitness-proportionally" do
      ranked = [
        { strategy_id: "a", fitness_score: 0.8, allocated_capital_usd: 100 },
        { strategy_id: "b", fitness_score: 0.2, allocated_capital_usd: 100 }
      ]
      config = { "available_capital_usd" => 0 }

      allocs = engine.send(:calculate_allocations, ranked, config)

      expect(allocs["a"]).to be > allocs["b"]
      expect(allocs["a"] + allocs["b"]).to be_within(0.01).of(200.0)
    end

    it "distributes equally when all fitness is zero" do
      ranked = [
        { strategy_id: "a", fitness_score: 0.0, allocated_capital_usd: 100 },
        { strategy_id: "b", fitness_score: 0.0, allocated_capital_usd: 100 }
      ]
      config = { "available_capital_usd" => 0 }

      allocs = engine.send(:calculate_allocations, ranked, config)

      expect(allocs["a"]).to eq(allocs["b"])
    end
  end

  describe "action determination" do
    it "promotes when capital increases > 10%" do
      action = engine.send(:determine_action,
        { fitness_score: 0.8, recent_candidate_scores: [] },
        120, 100, 0.1, 3)

      expect(action).to eq("promoted")
    end

    it "demotes when capital decreases > 10%" do
      action = engine.send(:determine_action,
        { fitness_score: 0.4, recent_candidate_scores: [] },
        80, 100, 0.1, 3)

      expect(action).to eq("demoted")
    end

    it "maintains when capital change < 10%" do
      action = engine.send(:determine_action,
        { fitness_score: 0.5, recent_candidate_scores: [] },
        95, 100, 0.1, 3)

      expect(action).to eq("maintained")
    end

    it "decommissions when fitness below threshold for consecutive epochs" do
      action = engine.send(:determine_action,
        { fitness_score: 0.05, recent_candidate_scores: [0.08, 0.06, 0.04] },
        10, 100, 0.1, 3)

      expect(action).to eq("decommissioned")
    end

    it "does not decommission if insufficient consecutive below-threshold scores" do
      action = engine.send(:determine_action,
        { fitness_score: 0.05, recent_candidate_scores: [0.08, 0.5, 0.04] },
        10, 100, 0.1, 3)

      expect(action).not_to eq("decommissioned")
    end
  end

  describe "breeding" do
    it "returns nil when fewer than 2 strategies" do
      ranked = [{ strategy_id: "a", fitness_score: 0.8, strategy_type: "momentum", parameters: {} }]
      result = engine.send(:build_breed_request, ranked, portfolio_config)
      expect(result).to be_nil
    end

    it "builds breed request from top 2 parents" do
      ranked = [
        { strategy_id: "a", fitness_score: 0.8, name: "Alpha", strategy_type: "llm_probability",
          pair: "KL_WEATHER/YES", venue_slug: "kalshi", trading_venue_id: "v1",
          risk_tier: "medium", parameters: { "temp" => 0.3 }, tick_interval_seconds: 300 },
        { strategy_id: "b", fitness_score: 0.6, name: "Beta", strategy_type: "llm_probability",
          pair: "KL_WEATHER/YES", venue_slug: "kalshi", trading_venue_id: "v1",
          risk_tier: "medium", parameters: { "temp" => 0.5 }, tick_interval_seconds: 300 }
      ]

      result = engine.send(:build_breed_request, ranked, portfolio_config)

      expect(result[:parent_a_id]).to eq("a")
      expect(result[:parent_b_id]).to eq("b")
      expect(result[:strategy_type]).to eq("llm_probability")
      expect(result[:name]).to include("Alpha")
      expect(result[:name]).to include("Beta")
      expect(result[:parameters]).to have_key("temp")
    end
  end
end

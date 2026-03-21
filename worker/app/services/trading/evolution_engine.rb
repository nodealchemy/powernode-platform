# frozen_string_literal: true

module Trading
  # Worker-side evolution computation engine.
  #
  # All scoring, ranking, capital allocation, and breeding decisions happen
  # locally using data fetched from the server via DataFetcher. No direct
  # database access — the server handles all DB mutations through three
  # lean endpoints: create_epoch, apply_actions, complete_epoch.
  class EvolutionEngine
    # Fitness component weights (matches EvolutionEpoch default)
    DEFAULT_WEIGHTS = {
      sharpe: 0.25, drawdown: 0.2, win_rate: 0.2,
      profit_factor: 0.15, risk_adjusted_return: 0.1, cost_efficiency: 0.1
    }.freeze

    # Regime suitability table (mirrors server-side MarketRegimeService::REGIME_SUITABILITY)
    REGIME_SUITABILITY = {
      "momentum"                => { trending_up: 1.0, trending_down: 1.0, mean_reverting: 0.2, sideways: 0.3, volatile: 0.6, calm: 0.8 },
      "mean_reversion"          => { trending_up: 0.3, trending_down: 0.3, mean_reverting: 1.0, sideways: 0.8, volatile: 0.7, calm: 0.9 },
      "arbitrage"               => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.8, sideways: 0.9, volatile: 0.9, calm: 0.7 },
      "tail_end_yield"          => { trending_up: 0.9, trending_down: 0.5, mean_reverting: 0.7, sideways: 0.8, volatile: 0.3, calm: 1.0 },
      "llm_probability"         => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.7, sideways: 0.7, volatile: 0.6, calm: 0.8 },
      "agent_ensemble"          => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.7, sideways: 0.7, volatile: 0.7, calm: 0.8 },
      "news_reactive"           => { trending_up: 0.7, trending_down: 0.7, mean_reverting: 0.6, sideways: 0.5, volatile: 0.9, calm: 0.4 },
      "sentiment_analysis"      => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.6, sideways: 0.5, volatile: 0.8, calm: 0.5 },
      "market_making"           => { trending_up: 0.6, trending_down: 0.6, mean_reverting: 0.9, sideways: 1.0, volatile: 0.3, calm: 0.9 },
      "combinatorial_arbitrage" => { trending_up: 0.7, trending_down: 0.7, mean_reverting: 0.8, sideways: 0.9, volatile: 0.8, calm: 0.8 },
      "longshot_fading"         => { trending_up: 0.7, trending_down: 0.8, mean_reverting: 0.9, sideways: 1.0, volatile: 0.4, calm: 1.0 },
      "prediction_market_making" => { trending_up: 0.6, trending_down: 0.6, mean_reverting: 0.9, sideways: 1.0, volatile: 0.3, calm: 1.0 },
      "cross_platform_arbitrage" => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.8, sideways: 0.9, volatile: 0.9, calm: 0.7 },
      "weather_model_alpha"     => { trending_up: 0.7, trending_down: 0.7, mean_reverting: 0.7, sideways: 0.8, volatile: 0.5, calm: 0.9 },
      "whale_copying"           => { trending_up: 0.8, trending_down: 0.7, mean_reverting: 0.6, sideways: 0.5, volatile: 0.9, calm: 0.6 },
      "spot_lag_arbitrage"      => { trending_up: 0.8, trending_down: 0.8, mean_reverting: 0.8, sideways: 0.9, volatile: 0.9, calm: 0.7 },
      "prediction_market"       => { trending_up: 0.7, trending_down: 0.7, mean_reverting: 0.7, sideways: 0.7, volatile: 0.7, calm: 0.7 },
      "yield_farming"           => { trending_up: 0.8, trending_down: 0.5, mean_reverting: 0.7, sideways: 0.7, volatile: 0.4, calm: 0.9 }
    }.freeze

    DEFAULT_SUITABILITY = { trending_up: 0.7, trending_down: 0.7, mean_reverting: 0.7, sideways: 0.7, volatile: 0.7, calm: 0.7 }.freeze

    RISK_FREE_RATE = 0.05 # 5% annualized

    def initialize(data_fetcher)
      @fetcher = data_fetcher
    end

    # Run a complete evolution epoch for a portfolio.
    #
    # @param portfolio_id [String] UUID of the portfolio
    # @param trigger_type [String] "scheduled", "manual", "mid_session_rebalance", "simulation"
    # @return [Hash] summary of the epoch
    def run_epoch!(portfolio_id, trigger_type: "scheduled")
      epoch_id = nil

      # 1. Create epoch + fetch strategy data from server
      setup = @fetcher.evolution_create_epoch(portfolio_id: portfolio_id, trigger_type: trigger_type)
      return { skipped: true, reason: setup["reason"] } if setup["skipped"]

      epoch_id = setup["epoch_id"]
      epoch_number = setup["epoch_number"]
      strategies = setup["strategies"] || []
      regimes = setup["regimes"] || {}
      config = (setup["portfolio_config"] || {}).merge("epoch_number" => epoch_number)

      # 2. Score strategies (local computation)
      scored = score_strategies(strategies, regimes)

      # 3. Rank by fitness
      ranked = scored.sort_by { |s| -s[:fitness_score] }
      ranked.each_with_index { |s, i| s[:rank] = i + 1 }

      # 4. Calculate capital allocations
      allocations = calculate_allocations(ranked, config)

      # 5. Determine actions (promote/demote/maintain/decommission)
      candidates = build_candidates(ranked, allocations, config)

      # 6. Build breed request from top performers
      breed_request = build_breed_request(ranked, config)

      # 7. Apply all actions to server
      result = @fetcher.evolution_apply_actions(
        epoch_id: epoch_id, candidates: candidates, breed_request: breed_request
      )

      # 8. Complete epoch
      complete_epoch(epoch_id, ranked, candidates, result)

      {
        epoch_id: epoch_id,
        strategies_evaluated: ranked.size,
        top_fitness: ranked.first&.dig(:fitness_score),
        bred_strategy: result["bred_strategy_name"]
      }
    rescue StandardError => e
      if epoch_id
        @fetcher.evolution_complete_epoch(epoch_id: epoch_id, error: e.message)
      end
      raise
    end

    private

    # ─── Scoring ──────────────────────────────────────────────

    def score_strategies(strategies, regimes)
      strategies.map do |s|
        fitness = if s["metrics"]
                    compute_metric_fitness(s, regimes)
                  else
                    compute_fallback_fitness(s)
                  end

        # Regime adjustment
        fitness = regime_adjusted_fitness(s["strategy_type"], fitness, regimes[s["pair"]])

        {
          strategy_id: s["id"],
          name: s["name"],
          strategy_type: s["strategy_type"],
          pair: s["pair"],
          status: s["status"],
          version_id: s["version_id"],
          allocated_capital_usd: s["allocated_capital_usd"].to_f,
          venue_slug: s["venue_slug"],
          trading_venue_id: s["trading_venue_id"],
          parameters: s["parameters"],
          tick_interval_seconds: s["tick_interval_seconds"],
          risk_tier: s["risk_tier"],
          fitness_score: fitness.round(6),
          fitness_breakdown: build_fitness_breakdown(s, fitness),
          recent_candidate_scores: s["recent_candidate_scores"] || []
        }
      end
    end

    def compute_metric_fitness(strategy, regimes)
      m = strategy["metrics"]
      daily_count = strategy["daily_return_count"] || 0

      components = {
        sharpe: daily_count >= 5 ? sigmoid_normalize(m["sharpe_ratio"] || 0, 1.5, 0.5) : 0.5,
        drawdown: normalize(-(m["max_drawdown_pct"] || 0).abs, -50, 0),
        win_rate: m["win_rate"] || 0,
        profit_factor: normalize(m["profit_factor"] || 0, 0, 5),
        risk_adjusted_return: normalize(m["pnl_usd"] || 0, -1000, 1000),
        cost_efficiency: compute_cost_efficiency(strategy)
      }

      DEFAULT_WEIGHTS.sum { |k, w| (components[k] || 0) * w }.clamp(0.0, 1.0)
    end

    def compute_fallback_fitness(strategy)
      base = 0.05

      base += 0.03 if strategy["allocated_capital_usd"].to_f > 0
      base += 0.03 if strategy["has_positions"]
      base += 0.03 if strategy["has_open_positions"]
      base += 0.03 if (strategy["position_count"] || 0) >= 3

      # Unrealized PnL contribution (capped at +0.05)
      unrealized = strategy["unrealized_pnl_usd"].to_f
      if unrealized > 0
        base += [unrealized / 100.0, 0.05].min
      end

      # Time-decay: fallback score decays as we expect real metrics to appear
      days_since_creation = strategy["days_since_creation"].to_f
      base *= 0.9**days_since_creation

      base.clamp(0.0, 0.20).round(6)
    end

    def compute_cost_efficiency(strategy)
      total_cost_usd = (strategy["budget_spent_cents"] || 0).to_f / 100.0
      return 0.5 if total_cost_usd <= 0 # Neutral for non-LLM strategies

      pnl = (strategy.dig("metrics", "pnl_usd") || 0).to_f
      return 0.0 if pnl <= 0

      normalize(pnl / total_cost_usd, 0, 10)
    end

    def regime_adjusted_fitness(strategy_type, base_fitness, regime)
      return base_fitness unless regime.is_a?(Hash) && regime["trend"]

      suitability_map = REGIME_SUITABILITY.fetch(strategy_type, DEFAULT_SUITABILITY)
      trend_suit = suitability_map[regime["trend"]&.to_sym] || 0.7

      adjusted = if trend_suit < 0.5 && base_fitness > 0.5
                   base_fitness * 1.25
                 elsif trend_suit > 0.8 && base_fitness < 0.3
                   base_fitness * 0.90
                 else
                   base_fitness
                 end
      adjusted.clamp(0.0, 1.0)
    end

    def build_fitness_breakdown(strategy, fitness)
      m = strategy["metrics"]
      breakdown = {
        fitness_score: fitness,
        total_llm_cost_usd: (strategy["budget_spent_cents"] || 0).to_f / 100.0,
        avg_tick_cost_usd: strategy["config_avg_tick_cost_usd"] || 0.0,
        llm_tick_count: strategy["config_llm_tick_count"] || 0
      }

      if m
        breakdown.merge!(
          sharpe_ratio: m["sharpe_ratio"],
          sortino_ratio: m["sortino_ratio"],
          max_drawdown_pct: m["max_drawdown_pct"],
          win_rate: m["win_rate"],
          profit_factor: m["profit_factor"],
          pnl_usd: m["pnl_usd"]
        )
      else
        breakdown[:using_fallback] = true
        breakdown[:open_position_count] = strategy["open_position_count"] || 0
        breakdown[:unrealized_pnl_usd] = strategy["unrealized_pnl_usd"] || 0.0
      end

      breakdown
    end

    # ─── Capital Allocation ───────────────────────────────────

    def calculate_allocations(ranked, config)
      return {} if ranked.empty?

      available = config["available_capital_usd"].to_f
      total_capital = available + ranked.sum { |s| s[:allocated_capital_usd] || 0 }

      total_fitness = ranked.sum { |s| s[:fitness_score] }

      if total_fitness.zero?
        equal_share = total_capital / ranked.size
        ranked.each_with_object({}) { |s, h| h[s[:strategy_id]] = equal_share }
      else
        ranked.each_with_object({}) do |s, h|
          share = s[:fitness_score] / total_fitness
          h[s[:strategy_id]] = (total_capital * share).round(2)
        end
      end
    end

    # ─── Action Determination ─────────────────────────────────

    def build_candidates(ranked, allocations, config)
      threshold = config["decommission_threshold"] || 0.1
      consecutive_epochs = config["decommission_consecutive_epochs"] || 3

      ranked.map do |s|
        new_capital = allocations[s[:strategy_id]] || 0
        old_capital = s[:allocated_capital_usd] || 0

        action = determine_action(s, new_capital, old_capital, threshold, consecutive_epochs)

        {
          strategy_id: s[:strategy_id],
          version_id: s[:version_id],
          fitness_score: s[:fitness_score],
          fitness_breakdown: s[:fitness_breakdown],
          rank: s[:rank],
          capital_before_usd: old_capital,
          capital_after_usd: action == "decommissioned" ? 0 : new_capital,
          action_taken: action
        }
      end
    end

    def determine_action(strategy, new_capital, old_capital, threshold, consecutive_epochs)
      # Check decommission eligibility
      if strategy[:fitness_score] < threshold
        recent = strategy[:recent_candidate_scores] || []
        if recent.size >= consecutive_epochs && recent.first(consecutive_epochs).all? { |s| s.to_f < threshold }
          return "decommissioned"
        end
      end

      # Capital-based action determination
      if old_capital > 0
        if new_capital > old_capital * 1.1
          "promoted"
        elsif new_capital < old_capital * 0.9
          "demoted"
        else
          "maintained"
        end
      else
        new_capital > 0 ? "promoted" : "maintained"
      end
    end

    # ─── Breeding ─────────────────────────────────────────────

    def build_breed_request(ranked, config)
      return nil if ranked.size < 2

      top_two = ranked.first(2)
      parent_a = top_two[0]
      parent_b = top_two[1]

      params_a = parent_a[:parameters] || {}
      params_b = parent_b[:parameters] || {}

      # Crossover: merge parameters from both parents with mutation
      child_params = crossover_parameters(params_a, params_b)

      epoch_number = config["epoch_number"] || 0

      {
        name: "#{parent_a[:name]} x #{parent_b[:name]} (gen#{epoch_number})",
        strategy_type: parent_a[:strategy_type],
        trading_venue_id: parent_a[:trading_venue_id],
        venue_slug: parent_a[:venue_slug],
        pair: parent_a[:pair],
        risk_tier: parent_a[:risk_tier] || "medium",
        parameters: child_params,
        tick_interval_seconds: evolve_tick_interval(parent_a, parent_b),
        parent_a_id: parent_a[:strategy_id],
        parent_b_id: parent_b[:strategy_id]
      }
    end

    def crossover_parameters(params_a, params_b)
      all_keys = (params_a.keys + params_b.keys).uniq
      child = {}

      all_keys.each do |key|
        val_a = params_a[key]
        val_b = params_b[key]

        child[key] = if val_a && val_b && val_a.is_a?(Numeric) && val_b.is_a?(Numeric)
                       base = rand < 0.5 ? val_a : val_b
                       mutation = base * rand(-0.1..0.1)
                       base + mutation
                     else
                       rand < 0.5 ? val_a : val_b
                     end
      end

      child
    end

    def evolve_tick_interval(parent_a, parent_b)
      val_a = parent_a[:tick_interval_seconds] || 300
      val_b = parent_b[:tick_interval_seconds] || 300
      base = rand < 0.5 ? val_a : val_b
      mutation = (base * rand(-0.2..0.2)).round
      (base + mutation).clamp(10, 300)
    end

    # ─── Epoch Completion ─────────────────────────────────────

    def complete_epoch(epoch_id, ranked, candidates, apply_result)
      results = {
        top_fitness: ranked.first&.dig(:fitness_score),
        avg_fitness: ranked.empty? ? 0 : (ranked.sum { |s| s[:fitness_score] } / ranked.size).round(6),
        total_strategies: ranked.size
      }

      counters = {
        evaluated: candidates.size,
        promoted: candidates.count { |c| c[:action_taken] == "promoted" },
        demoted: candidates.count { |c| c[:action_taken] == "demoted" },
        decommissioned: candidates.count { |c| c[:action_taken] == "decommissioned" },
        bred: apply_result&.dig("bred_strategy_id") ? 1 : 0
      }

      @fetcher.evolution_complete_epoch(epoch_id: epoch_id, results: results, counters: counters)
    end

    # ─── Math Helpers ─────────────────────────────────────────

    def normalize(value, min, max)
      return 0 if max == min
      ((value - min).to_f / (max - min)).clamp(0.0, 1.0)
    end

    def sigmoid_normalize(value, midpoint, steepness = 1.0)
      1.0 / (1.0 + Math.exp(-steepness * (value - midpoint)))
    end
  end
end

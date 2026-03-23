# frozen_string_literal: true

module Trading
  # Adaptive training decision engine — proactively seeks profitable
  # strategy/market combinations instead of passively running fixed configs.
  #
  # Pure decision engine: no DB access, no API calls. Returns action
  # descriptors that the training job interprets and executes via DataFetcher.
  #
  # Four decision points in the session lifecycle:
  #   1. plan_session!   — pre-session intelligence (strategy selection, capital allocation)
  #   2. assess_tick!    — per-tick fast pruning of zero-performers
  #   3. hunt!           — periodic market rotation and strategy experimentation
  #   4. reflect!        — post-session learning extraction
  #
  # Opt-in via session config: { profit_hunter_enabled: true }
  class ProfitHunter
    # Default config values (overridable via session config)
    DEFAULTS = {
      reserve_pct: 0.15,          # 15% capital held back for hunting
      fast_prune_ticks: 3,        # Prune after N consecutive zero ticks
      hunt_interval: 5,           # Hunt every N ticks
      max_experiments: 3,         # Max concurrent experimental strategies
      llm_budget_usd: 2.0,        # Cap LLM spend on exploration
      market_dead_ticks: 5,       # Market considered dead after N zero-signal ticks
      exploitation_pct: 0.65,     # Exploitation allocation in plan
      exploration_pct: 0.25,      # Exploration allocation in plan
      plan_reserve_pct: 0.10      # Reserve allocation in plan
    }.freeze

    # Strategy types that don't require LLM calls (prefer these for experiments)
    ZERO_LLM_TYPES = %w[
      arbitrage momentum mean_reversion tail_end_yield longshot_fading
      combinatorial_arbitrage market_making prediction_market_making
      cross_platform_arbitrage spot_lag_arbitrage whale_copying
      weather_model_alpha yield_farming prediction_market
    ].freeze

    LLM_TYPES = %w[llm_probability agent_ensemble news_reactive sentiment_analysis].freeze

    attr_reader :reserve_capital, :pruned_strategies, :hunt_history,
                :experiments_active, :llm_spend_usd, :config

    def initialize(config = {})
      @config = DEFAULTS.merge(config.transform_keys(&:to_sym))
      @strategy_zero_ticks = {}       # strategy_id => consecutive zero-tick count
      @strategy_cumulative_pnl = {}   # strategy_id => cumulative PnL
      @type_performance = {}          # strategy_type => { pnl:, signals:, ticks: }
      @market_zero_ticks = {}         # market_pair => consecutive zero-signal ticks
      @markets_tried = Set.new        # market_pairs already attempted (avoid retries)
      @types_tried_per_market = {}    # market_pair => Set of strategy types tried
      @reserve_capital = 0.0
      @pruned_strategies = []
      @hunt_history = []
      @experiments_active = 0
      @llm_spend_usd = 0.0
    end

    # ─── Decision Point 1: PLAN ──────────────────────────────────
    #
    # Pre-session intelligence: compose starting portfolio based on
    # cross-session scorecards and current market regime.
    #
    # @param scorecards [Hash] strategy_type => scorecard hash from StrategyIntelligenceService
    # @param regime [Hash] current market regime from MarketRegimeService
    # @param available_types [Array<String>] all strategy types available
    # @param venue_slug [String] venue identifier
    # @return [Hash] { strategy_types:, capital_allocation:, exploration_budget_pct: }
    def plan_session!(scorecards:, regime: nil, available_types: [], venue_slug: nil)
      return default_plan(available_types) if scorecards.nil? || scorecards.empty?

      regime_key = regime&.dig("trend") || regime&.dig(:trend) || "sideways"

      # Score each available type
      scored = available_types.map do |st|
        sc = scorecards[st]
        regime_score = regime_suitability(st, regime_key)

        if sc && sc[:sessions_count].to_i > 0
          # Known type — score by historical performance + regime fit
          venue_data = venue_slug ? sc[:venue_scorecards]&.dig(venue_slug) : nil
          effective_win_rate = venue_data ? venue_data[:win_rate].to_f : sc[:win_rate].to_f
          effective_pnl = venue_data ? venue_data[:avg_pnl].to_f : sc[:avg_pnl_per_session].to_f
          confidence = sc[:confidence].to_f

          score = (effective_win_rate * 40) +
                  (effective_pnl * 3) +
                  (regime_score * 20) +
                  (confidence * 10)

          # Penalize suppressed, boost amplified
          score *= 0.3 if sc[:status].to_s == "suppressed"
          score *= 1.3 if sc[:status].to_s == "amplified"

          { type: st, score: score.round(2), bucket: :exploitation, data_points: sc[:sessions_count].to_i }
        else
          # Unknown type — exploration candidate, scored by regime fit only
          { type: st, score: (regime_score * 15).round(2), bucket: :exploration, data_points: 0 }
        end
      end

      # Sort by score descending
      scored.sort_by! { |s| -s[:score] }

      # Partition into exploitation vs exploration
      exploitation = scored.select { |s| s[:bucket] == :exploitation && s[:score] > 0 }
      exploration = scored.select { |s| s[:bucket] == :exploration }

      # Build allocation
      exploitation_pct = @config[:exploitation_pct]
      exploration_pct = @config[:exploration_pct]
      reserve_pct = @config[:plan_reserve_pct]

      # Pick top exploitation types
      exploit_types = exploitation.first([exploitation.size, 5].min).map { |s| s[:type] }
      explore_types = exploration.first([exploration.size, 3].min).map { |s| s[:type] }

      # If no exploitation data, shift budget to exploration
      if exploit_types.empty?
        exploration_pct += exploitation_pct
        exploitation_pct = 0.0
      end

      all_types = (exploit_types + explore_types).uniq
      capital_allocation = {}

      # Exploitation types get proportional share of exploitation budget
      if exploit_types.any?
        exploit_scores = exploitation.first(exploit_types.size)
        total_score = exploit_scores.sum { |s| s[:score].abs } + 0.01
        exploit_types.each_with_index do |t, i|
          weight = exploit_scores[i][:score].abs / total_score
          capital_allocation[t] = (exploitation_pct * weight).round(4)
        end
      end

      # Exploration types split exploration budget evenly
      if explore_types.any?
        per_explore = exploration_pct / explore_types.size
        explore_types.each { |t| capital_allocation[t] = per_explore.round(4) }
      end

      {
        strategy_types: all_types,
        capital_allocation: capital_allocation,
        exploitation_types: exploit_types,
        exploration_types: explore_types,
        exploration_budget_pct: exploration_pct,
        reserve_pct: reserve_pct,
        scored_rankings: scored.first(10)
      }
    end

    # ─── Decision Point 2: ASSESS ────────────────────────────────
    #
    # Per-tick assessment: track each strategy's performance, identify
    # zero-performers for fast pruning.
    #
    # @param tick_num [Integer] current tick number
    # @param strategies_state [Array<Hash>] per-strategy results from this tick
    #   Each: { id:, type:, pair:, signals_count:, pnl_delta:, cumulative_pnl: }
    # @return [Hash] { actions: [:fast_prune], prune_ids: [...], reserve_released: Float }
    def assess_tick!(tick_num, strategies_state)
      actions = []
      prune_ids = []
      reserve_released = 0.0

      strategies_state.each do |state|
        sid = state[:id] || state["id"]
        stype = state[:type] || state["type"]
        pair = state[:pair] || state["pair"]
        signals = (state[:signals_count] || state["signals_count"]).to_i
        pnl_delta = (state[:pnl_delta] || state["pnl_delta"]).to_f
        capital = (state[:allocated_capital] || state["allocated_capital"]).to_f

        # Track cumulative PnL
        @strategy_cumulative_pnl[sid] = (@strategy_cumulative_pnl[sid] || 0.0) + pnl_delta

        # Track per-type performance
        @type_performance[stype] ||= { pnl: 0.0, signals: 0, ticks: 0 }
        @type_performance[stype][:pnl] += pnl_delta
        @type_performance[stype][:signals] += signals
        @type_performance[stype][:ticks] += 1

        # Track market-level signals
        if pair
          if signals == 0
            @market_zero_ticks[pair] = (@market_zero_ticks[pair] || 0) + 1
          else
            @market_zero_ticks[pair] = 0
          end
          @markets_tried.add(pair)
          @types_tried_per_market[pair] ||= Set.new
          @types_tried_per_market[pair].add(stype)
        end

        # Fast prune: consecutive zero ticks
        if signals == 0 && pnl_delta.abs < 0.001
          @strategy_zero_ticks[sid] = (@strategy_zero_ticks[sid] || 0) + 1
        else
          @strategy_zero_ticks[sid] = 0
        end

        if @strategy_zero_ticks[sid] >= @config[:fast_prune_ticks]
          prune_ids << sid
          reserve_released += capital
          @pruned_strategies << { id: sid, type: stype, pair: pair, reason: :zero_ticks, tick: tick_num }
        end
      end

      @reserve_capital += reserve_released

      result = { actions: [], prune_ids: prune_ids, reserve_released: reserve_released }
      result[:actions] << :fast_prune if prune_ids.any?
      result
    end

    # ─── Decision Point 3: HUNT ──────────────────────────────────
    #
    # Periodic hunting: rotate dead markets, experiment with new
    # strategy/market combinations, deploy reserve capital.
    #
    # @param tick_num [Integer] current tick number
    # @param strategies_state [Array<Hash>] current strategy states
    # @param available_markets [Array<Hash>] all discovered markets
    # @param regime [Hash, nil] current market regime
    # @return [Hash] { new_assignments:, market_rotations:, type_experiments:, skip_reason: }
    def hunt!(tick_num, strategies_state, available_markets: [], regime: nil)
      return { skip_reason: "not_hunt_tick" } unless (tick_num % @config[:hunt_interval]).zero?
      return { skip_reason: "max_experiments_reached" } if @experiments_active >= @config[:max_experiments]
      return { skip_reason: "no_reserve_capital" } if @reserve_capital <= 0

      new_assignments = []
      market_rotations = []
      type_experiments = []

      regime_key = regime&.dig("trend") || regime&.dig(:trend) || "sideways"

      # 1. Dead market rotation — find markets with zero signals across ALL types
      dead_markets = find_dead_markets(strategies_state)

      # 2. Generate hypotheses from existing performance data
      hypotheses = generate_hypotheses(strategies_state, available_markets, regime_key)

      # 3. Score and rank hypotheses
      ranked = hypotheses.sort_by { |h| -h[:expected_score] }

      # 4. Deploy top hypotheses up to experiment limit and reserve budget
      slots = @config[:max_experiments] - @experiments_active
      capital_per_experiment = @reserve_capital / [slots, 1].max

      ranked.first(slots).each do |hypothesis|
        break if @reserve_capital < capital_per_experiment * 0.5

        # Skip LLM types if budget exhausted
        if LLM_TYPES.include?(hypothesis[:strategy_type]) && @llm_spend_usd >= @config[:llm_budget_usd]
          next
        end

        assignment = {
          pair: hypothesis[:pair],
          strategy_type: hypothesis[:strategy_type],
          capital: [capital_per_experiment, @reserve_capital].min.round(2),
          hypothesis: hypothesis[:pattern],
          expected_score: hypothesis[:expected_score]
        }

        new_assignments << assignment
        @reserve_capital -= assignment[:capital]
        @experiments_active += 1

        @hunt_history << {
          tick: tick_num,
          action: :deploy,
          assignment: assignment
        }

        # Track what we've tried
        @markets_tried.add(hypothesis[:pair])
        @types_tried_per_market[hypothesis[:pair]] ||= Set.new
        @types_tried_per_market[hypothesis[:pair]].add(hypothesis[:strategy_type])
      end

      # 5. Identify market rotations needed
      dead_markets.each do |dead_pair|
        # Find a replacement market not yet tried
        replacement = find_untried_market(available_markets, dead_pair)
        next unless replacement

        market_rotations << {
          dead_pair: dead_pair,
          replacement_pair: replacement[:pair] || replacement["pair"],
          reason: "#{@market_zero_ticks[dead_pair]} consecutive zero-signal ticks"
        }
      end

      {
        new_assignments: new_assignments,
        market_rotations: market_rotations,
        type_experiments: type_experiments,
        hypotheses_generated: hypotheses.size,
        hypotheses_deployed: new_assignments.size,
        reserve_remaining: @reserve_capital.round(2)
      }
    end

    # ─── Decision Point 4: REFLECT ───────────────────────────────
    #
    # Post-session learning: package results for scorecard updates
    # and profitability heatmap.
    #
    # @param session_summary [Hash] final session metrics
    # @return [Hash] { learnings:, heatmap_updates:, type_rankings: }
    def reflect!(session_summary = {})
      learnings = []
      heatmap_updates = {}

      # Analyze per-type performance
      @type_performance.each do |stype, perf|
        next if perf[:ticks].to_i == 0

        avg_pnl = perf[:pnl] / perf[:ticks]
        signals_per_tick = perf[:signals].to_f / perf[:ticks]

        heatmap_updates[stype] = {
          avg_pnl_per_tick: avg_pnl.round(4),
          total_pnl: perf[:pnl].round(4),
          signals_per_tick: signals_per_tick.round(4),
          ticks_evaluated: perf[:ticks]
        }

        # Learning: which types were profitable vs duds
        if perf[:pnl] > 0
          learnings << { type: stype, outcome: :profitable, pnl: perf[:pnl].round(4), ticks: perf[:ticks] }
        elsif perf[:signals] == 0
          learnings << { type: stype, outcome: :no_signals, pnl: 0, ticks: perf[:ticks] }
        else
          learnings << { type: stype, outcome: :unprofitable, pnl: perf[:pnl].round(4), ticks: perf[:ticks] }
        end
      end

      # Analyze hunt effectiveness
      hunt_deployments = @hunt_history.select { |h| h[:action] == :deploy }
      hunt_results = hunt_deployments.map do |deployment|
        pair = deployment.dig(:assignment, :pair)
        stype = deployment.dig(:assignment, :strategy_type)
        perf = @type_performance[stype]
        { pair: pair, type: stype, hypothesis: deployment.dig(:assignment, :hypothesis),
          pnl: perf ? perf[:pnl].round(4) : 0.0,
          confirmed: perf && perf[:pnl] > 0 }
      end

      confirmed = hunt_results.count { |h| h[:confirmed] }
      rejected = hunt_results.count { |h| !h[:confirmed] }

      # Type rankings by PnL
      type_rankings = @type_performance
        .sort_by { |_, p| -p[:pnl] }
        .map { |t, p| { type: t, pnl: p[:pnl].round(4), signals: p[:signals], ticks: p[:ticks] } }

      {
        learnings: learnings,
        heatmap_updates: heatmap_updates,
        type_rankings: type_rankings,
        hunt_results: hunt_results,
        hypotheses_confirmed: confirmed,
        hypotheses_rejected: rejected,
        total_pruned: @pruned_strategies.size,
        reserve_remaining: @reserve_capital.round(2)
      }
    end

    # Register LLM cost from an experiment evaluation
    def record_llm_cost(usd)
      @llm_spend_usd += usd.to_f
    end

    # Called when an experiment strategy is decommissioned or completes
    def release_experiment_slot(capital_returned = 0.0)
      @experiments_active = [@experiments_active - 1, 0].max
      @reserve_capital += capital_returned
    end

    private

    def default_plan(available_types)
      {
        strategy_types: available_types,
        capital_allocation: {},
        exploitation_types: available_types,
        exploration_types: [],
        exploration_budget_pct: 0.0,
        reserve_pct: @config[:reserve_pct],
        scored_rankings: []
      }
    end

    # Find markets where ALL strategy types produce zero signals
    def find_dead_markets(strategies_state)
      market_signals = {}

      strategies_state.each do |state|
        pair = state[:pair] || state["pair"]
        next unless pair

        signals = (state[:signals_count] || state["signals_count"]).to_i
        market_signals[pair] = (market_signals[pair] || 0) + signals
      end

      @market_zero_ticks.select { |pair, count|
        count >= @config[:market_dead_ticks] && market_signals.fetch(pair, 0) == 0
      }.keys
    end

    # Generate hypotheses for new strategy/market combinations
    def generate_hypotheses(strategies_state, available_markets, regime_key)
      hypotheses = []

      # Pattern 1: Price bracket expansion — winning price-specialist on similar markets
      hypotheses.concat(price_bracket_hypotheses(strategies_state, available_markets))

      # Pattern 2: Type cycling — failed type X on market M, try type Y
      hypotheses.concat(type_cycling_hypotheses(strategies_state, available_markets, regime_key))

      # Pattern 3: Winner cloning — clone successful strategy params to similar markets
      hypotheses.concat(winner_cloning_hypotheses(strategies_state, available_markets))

      # Pattern 4: Regime-strategy match — deploy regime-appropriate types not yet running
      hypotheses.concat(regime_match_hypotheses(strategies_state, regime_key, available_markets))

      # Deduplicate by pair+type
      seen = Set.new
      hypotheses.select do |h|
        key = "#{h[:pair]}:#{h[:strategy_type]}"
        next false if seen.include?(key)
        # Skip already-tried combinations
        tried = @types_tried_per_market[h[:pair]]
        next false if tried&.include?(h[:strategy_type])
        seen.add(key)
        true
      end
    end

    # Pattern 1: If tail_end_yield works on market A (>0.85 yes_price),
    # deploy it on markets B,C that also have >0.85 yes_price
    def price_bracket_hypotheses(strategies_state, available_markets)
      hypotheses = []
      price_specialists = {
        "tail_end_yield" => (0.80..0.99),
        "longshot_fading" => (0.02..0.25)
      }

      strategies_state.each do |state|
        stype = state[:type] || state["type"]
        next unless price_specialists.key?(stype)
        next unless (state[:signals_count] || state["signals_count"]).to_i > 0

        range = price_specialists[stype]
        # Find other markets in the same price bracket
        available_markets.each do |market|
          price = (market[:yes_price] || market["yes_price"]).to_f
          pair = market[:pair] || market["pair"] || market[:pairs]&.first || market["pairs"]&.first
          next unless pair
          next if @markets_tried.include?(pair)
          next unless range.cover?(price)

          hypotheses << {
            pair: pair,
            strategy_type: stype,
            pattern: :price_bracket_expansion,
            expected_score: 0.7
          }
        end
      end

      hypotheses
    end

    # Pattern 2: Strategy type X produced $0 on market M for 5 ticks.
    # Try type Y (highest regime suitability) on that market instead.
    def type_cycling_hypotheses(strategies_state, available_markets, regime_key)
      hypotheses = []

      strategies_state.each do |state|
        sid = state[:id] || state["id"]
        stype = state[:type] || state["type"]
        pair = state[:pair] || state["pair"]

        # Only cycle types that have been failing
        next unless @strategy_zero_ticks[sid].to_i >= @config[:fast_prune_ticks]
        next unless pair

        # Find alternative types for this market, sorted by regime suitability
        tried = @types_tried_per_market[pair] || Set.new
        candidates = (ZERO_LLM_TYPES - tried.to_a - [stype])
          .sort_by { |t| -regime_suitability(t, regime_key) }

        next if candidates.empty?

        best = candidates.first
        hypotheses << {
          pair: pair,
          strategy_type: best,
          pattern: :type_cycling,
          expected_score: regime_suitability(best, regime_key) * 0.6
        }
      end

      hypotheses
    end

    # Pattern 3: Strategy A is profitable on market X. Market Y has a
    # similar profile (same category, similar price). Clone A → Y.
    def winner_cloning_hypotheses(strategies_state, available_markets)
      hypotheses = []

      # Find winning strategies
      winners = strategies_state.select do |state|
        pnl = @strategy_cumulative_pnl[state[:id] || state["id"]] || 0
        pnl > 0
      end

      winners.each do |winner|
        stype = winner[:type] || winner["type"]
        pair = winner[:pair] || winner["pair"]
        next unless pair

        # Find markets with similar characteristics
        available_markets.each do |market|
          mpair = market[:pair] || market["pair"] || market[:pairs]&.first || market["pairs"]&.first
          next unless mpair
          next if mpair == pair
          next if @markets_tried.include?(mpair)

          hypotheses << {
            pair: mpair,
            strategy_type: stype,
            pattern: :winner_cloning,
            expected_score: 0.5
          }
        end
      end

      hypotheses.first(5) # Limit to avoid explosion
    end

    # Pattern 4: Regime shifted. A high-suitability type is not deployed.
    def regime_match_hypotheses(strategies_state, regime_key, available_markets)
      hypotheses = []
      deployed_types = strategies_state.map { |s| s[:type] || s["type"] }.uniq

      # Find types with high regime suitability that aren't deployed
      undeployed = ZERO_LLM_TYPES.reject { |t| deployed_types.include?(t) }
      high_suitability = undeployed.select { |t| regime_suitability(t, regime_key) >= 0.8 }

      high_suitability.each do |stype|
        # Find a suitable market
        market = available_markets.find do |m|
          mpair = m[:pair] || m["pair"] || m[:pairs]&.first || m["pairs"]&.first
          mpair && !@markets_tried.include?(mpair)
        end

        next unless market

        mpair = market[:pair] || market["pair"] || market[:pairs]&.first || market["pairs"]&.first
        hypotheses << {
          pair: mpair,
          strategy_type: stype,
          pattern: :regime_strategy_match,
          expected_score: regime_suitability(stype, regime_key) * 0.8
        }
      end

      hypotheses
    end

    def find_untried_market(available_markets, dead_pair)
      available_markets.find do |m|
        pair = m[:pair] || m["pair"] || m[:pairs]&.first || m["pairs"]&.first
        pair && pair != dead_pair && !@markets_tried.include?(pair)
      end
    end

    # Regime suitability score for a strategy type (0.0-1.0)
    # Mirrors EvolutionEngine::REGIME_SUITABILITY
    def regime_suitability(strategy_type, regime_key)
      table = Trading::EvolutionEngine::REGIME_SUITABILITY[strategy_type]
      return 0.7 unless table # default for unknown types

      table[regime_key.to_sym] || 0.7
    end
  end
end

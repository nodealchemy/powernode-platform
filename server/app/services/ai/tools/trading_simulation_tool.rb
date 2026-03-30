# frozen_string_literal: true

require "zlib"

module Ai
  module Tools
    class TradingSimulationTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.manage"

      def self.definition
        {
          name: "trading_simulation_management",
          description: "Manage trading simulations and AI training sessions",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            simulation_id: { type: "string", required: false, description: "Simulation ID" },
            session_id: { type: "string", required: false, description: "Training session ID" },
            strategy_id: { type: "string", required: false, description: "Strategy ID or name" },
            status: { type: "string", required: false, description: "Filter by status" },
            config: { type: "object", required: false, description: "Simulation or training config" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_simulations" => {
            description: "List trading simulations with optional status filter",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: setup, running, paused, completed, failed" }
            }
          },
          "trading_get_simulation" => {
            description: "Get detailed simulation information including progress and results",
            parameters: {
              simulation_id: { type: "string", required: true, description: "Simulation ID" }
            }
          },
          "trading_create_simulation" => {
            description: "Create a new trading simulation for a strategy",
            parameters: {
              strategy_id: { type: "string", required: true, description: "Strategy ID or name to simulate" },
              config: { type: "object", required: false, description: "Simulation configuration" }
            }
          },
          "trading_run_simulation" => {
            description: "Start or resume a simulation",
            parameters: {
              simulation_id: { type: "string", required: true, description: "Simulation ID" }
            }
          },
          "trading_pause_simulation" => {
            description: "Pause a running simulation",
            parameters: {
              simulation_id: { type: "string", required: true, description: "Simulation ID" }
            }
          },
          "trading_simulation_report" => {
            description: "Get simulation results report (must be completed)",
            parameters: {
              simulation_id: { type: "string", required: true, description: "Simulation ID" }
            }
          },
          "trading_list_training_sessions" => {
            description: "List AI training sessions with optional status filter",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status: scheduled, pending, initializing, running, paused, completed, failed, cancelled" }
            }
          },
          "trading_get_training_session" => {
            description: "Get training session details including progress and metrics",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_create_training_session" => {
            description: "Create a new AI training session. Defaults to continuous mode. All params can be passed at top level or nested under 'config'.",
            parameters: {
              strategy_id: { type: "string", required: false, description: "Strategy ID or name (optional)" },
              config: { type: "object", required: false, description: "Training session configuration (alternative: pass params at top level)" },
              name: { type: "string", required: false, description: "Session name" },
              mode: { type: "string", required: false, description: "Session mode: 'continuous' (default) or 'fixed_ticks'" },
              strategy_types: { type: "array", required: false, description: "Strategy types to run" },
              market_count: { type: "integer", required: false, description: "Number of markets to discover" },
              tick_count: { type: "integer", required: false, description: "Number of ticks to run (only for fixed_ticks mode)" },
              tick_interval: { type: "integer", required: false, description: "Seconds between ticks" },
              initial_balance: { type: "number", required: false, description: "Starting balance in USD" },
              venue_slug: { type: "string", required: false, description: "Trading venue slug (e.g. 'kalshi')" },
              risk_tier: { type: "string", required: false, description: "Risk tier (low/medium/high)" },
              include_classic: { type: "boolean", required: false, description: "Deprecated — use strategy_types array to specify all desired types" },
              bypass_suppression: { type: "boolean", required: false, description: "Bypass intelligence suppression — allow strategies that would normally be blocked by poor historical performance" },
              use_performance_sizing: { type: "boolean", required: false, description: "Enable performance-based position sizing (scales size by win rate)" },
              probability_min: { type: "number", required: false, description: "Min probability filter for market selection" },
              probability_max: { type: "number", required: false, description: "Max probability filter for market selection" },
              min_volume_24h: { type: "number", required: false, description: "Min 24h volume filter" },
              compounding_enabled: { type: "boolean", required: false, description: "Enable profit compounding" },
              compounding_threshold_pct: { type: "number", required: false, description: "P&L threshold % to trigger compounding" },
              compounding_reinvest_pct: { type: "integer", required: false, description: "Percentage of profits to reinvest (0-100)" },
              confidence_threshold: { type: "number", required: false, description: "Minimum confidence score to enter positions" },
              rebalance_enabled: { type: "boolean", required: false, description: "Enable mid-session capital rebalancing (shifts capital from losers to winners)" },
              rebalance_interval_ticks: { type: "integer", required: false, description: "Rebalance every N ticks (default: 5)" },
              rebalance_smoothing_factor: { type: "number", required: false, description: "0.0=no change, 1.0=full redistribution (default: 0.5)" },
              rebalance_min_ticks: { type: "integer", required: false, description: "Minimum ticks before first rebalance (default: 3)" },
              rebalance_decommission_enabled: { type: "boolean", required: false, description: "Allow mid-session strategy decommission for severe underperformers (default: true)" },
              include_series: { type: "array", items: { type: "string" }, required: false, description: "Series ticker prefixes to scope discovery (e.g. ['KXFED', 'KXBTC']). Drastically speeds up discovery by skipping irrelevant series." },
              exclude_series: { type: "array", items: { type: "string" }, required: false, description: "Series ticker prefixes to exclude from discovery" },
              scheduled_for: { type: "string", required: false, description: "ISO8601 datetime to schedule session for future start (sets status to 'scheduled'). Overseer auto-starts when time arrives." },
              duration_minutes: { type: "integer", required: false, description: "Session duration in minutes for continuous mode. Sets ends_at relative to start time (or scheduled_for). Overseer auto-completes when expired. Omit for indefinite." },
              profit_hunter_enabled: { type: "boolean", required: false, description: "Enable adaptive profit hunting — auto-prunes zero-performers, rotates dead markets, deploys reserve capital on new strategy/market combos" },
              profit_hunter_reserve_pct: { type: "number", required: false, description: "Fraction of capital held in reserve for hunting (default: 0.15 = 15%)" },
              profit_hunter_fast_prune_ticks: { type: "integer", required: false, description: "Prune strategies after N consecutive zero-result ticks (default: 3)" },
              profit_hunter_hunt_interval: { type: "integer", required: false, description: "Run hunting loop every N ticks (default: 5)" },
              profit_hunter_max_experiments: { type: "integer", required: false, description: "Max concurrent experimental strategies from hunting (default: 3)" },
              profit_hunter_llm_budget_usd: { type: "number", required: false, description: "Cap LLM spend on exploration — prefers zero-LLM strategy types (default: 2.0)" }
            }
          },
          "trading_cancel_training_session" => {
            description: "Cancel a running or pending training session",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_complete_training_session" => {
            description: "Gracefully complete a running training session early — closes positions, generates full report, marks as completed",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID or name" }
            }
          },
          "trading_retry_training_session" => {
            description: "Retry a failed or cancelled training session (resets to pending)",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_delete_training_session" => {
            description: "Delete a non-running training session",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_training_session_report" => {
            description: "Get full results report for a completed training session",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_get_strategy_params" => {
            description: "Get current effective parameters for a strategy type (all layers merged: hardcoded → global defaults → venue overrides)",
            parameters: {
              strategy_type: { type: "string", required: true, description: "Strategy type (e.g. 'momentum', 'prediction_market_making')" },
              venue_slug: { type: "string", required: false, description: "Venue slug to include venue-specific overrides" }
            }
          },
          "trading_update_strategy_params" => {
            description: "Update a single training parameter for a strategy type. Updates global defaults or venue-specific overrides.",
            parameters: {
              strategy_type: { type: "string", required: true, description: "Strategy type (e.g. 'momentum', 'prediction_market_making')" },
              key: { type: "string", required: true, description: "Parameter key to update (e.g. 'entry_threshold', 'stop_loss_pct')" },
              value: { type: "string", required: true, description: "New value for the parameter" },
              venue_slug: { type: "string", required: false, description: "If set, updates venue-specific override instead of global default" }
            }
          },
          "trading_create_dry_run_session" => {
            description: "Create a lightweight dry-run session testing ALL strategy types (~3-5 min). " \
                         "Produces pnl_by_strategy_type_and_category for the learning pipeline.",
            parameters: {
              venue_slug: { type: "string", required: false, description: "Venue (default: kalshi)" },
              tick_count: { type: "integer", required: false, description: "Ticks (default: 5, max: 15)" }
            }
          },
          "trading_seed_strategy_defaults" => {
            description: "Seed all hardcoded training parameters into shared memory as dynamic defaults. Idempotent — preserves existing modifications.",
            parameters: {}
          },
          "trading_seed_profit_formula" => {
            description: "Seed the Profit Formula portfolio — tuned parameters for 9 zero-LLM-cost strategies (arbitrage, tail_end_yield, combinatorial_arbitrage, longshot_fading, prediction_market_making, mean_reversion, momentum, cross_platform_arbitrage, spot_lag_arbitrage). Overwrites global defaults with empirically-optimized values from 136 training runs. Also sets venue-specific overrides for Polymarket (zero fees) and Kalshi.",
            parameters: {}
          },
          "trading_import_historical_data" => {
            description: "Import historical price data for a venue+ticker into PriceSnapshots for backtesting. Supports Kalshi (candlestick API) and Polymarket (Gamma API).",
            parameters: {
              venue_slug: { type: "string", required: true, description: "Venue slug: 'kalshi' or 'polymarket'" },
              ticker: { type: "string", required: false, description: "Ticker or condition_id to import (e.g. 'KXFED' for Kalshi event, condition_id for PM)" },
              slug: { type: "string", required: false, description: "Polymarket event slug (alternative to ticker for PM)" },
              interval: { type: "string", required: false, description: "Candle interval (default: '1h')" },
              limit: { type: "integer", required: false, description: "Max pairs to import from registry (default: 50)" }
            }
          },
          "trading_run_backtest" => {
            description: "Create a training session against the Simulator venue with historical_replay mode. Requires historical data to be imported first via trading_import_historical_data.",
            parameters: {
              strategy_types: { type: "array", required: false, description: "Strategy types to backtest (default: profit formula strategies)" },
              tick_count: { type: "integer", required: false, description: "Number of ticks (default: 50)" },
              tick_interval: { type: "integer", required: false, description: "Seconds between ticks (default: 5)" },
              initial_balance: { type: "number", required: false, description: "Starting balance (default: 10000)" },
              name: { type: "string", required: false, description: "Session name" },
              strategy_overrides: { type: "object", required: false, description: "Per-strategy parameter overrides" },
              start_at: { type: "string", required: false, description: "Backtest start (ISO8601, default: 7 days ago)" },
              end_at: { type: "string", required: false, description: "Backtest end (ISO8601, default: now)" },
              replay_interval_hours: { type: "number", required: false, description: "Hours per tick (default: 1)" }
            }
          },
          "trading_parameter_sweep" => {
            description: "Run N backtests with varying parameter combinations for a strategy type. Creates batch sessions against Simulator with historical_replay, returns ranked results.",
            parameters: {
              strategy_type: { type: "string", required: true, description: "Strategy type to sweep (e.g. 'prediction_market_making')" },
              param_ranges: { type: "object", required: true, description: "Parameter ranges: { 'kelly_fraction': [0.15, 0.20, 0.25], 'stop_loss_pct': [2.0, 3.0] }" },
              sweep_id: { type: "string", required: false, description: "Existing sweep ID to collect results (skip creation)" },
              method: { type: "string", required: false, description: "Combination method: 'grid' (default) or 'lhs'" },
              max_combos: { type: "integer", required: false, description: "Max parameter combinations (default: 64)" },
              tick_count: { type: "integer", required: false, description: "Ticks per backtest (default: 50)" },
              initial_balance: { type: "number", required: false, description: "Starting balance (default: 10000)" },
              promote_best: { type: "boolean", required: false, description: "Auto-promote best params to global defaults if profitable" }
            }
          }
        }
      end

      def self.permitted?(agent:)
        return false unless defined?(::Trading)
        super
      end

      protected

      def call(params)
        require_trading!

        case params[:action]
        when "trading_list_simulations" then list_simulations(params)
        when "trading_get_simulation" then get_simulation(params)
        when "trading_create_simulation" then create_simulation(params)
        when "trading_run_simulation" then run_simulation(params)
        when "trading_pause_simulation" then pause_simulation(params)
        when "trading_simulation_report" then simulation_report(params)
        when "trading_list_training_sessions" then list_training_sessions(params)
        when "trading_get_training_session" then get_training_session(params)
        when "trading_create_training_session" then create_training_session(params)
        when "trading_cancel_training_session" then cancel_training_session(params)
        when "trading_complete_training_session" then complete_training_session(params)
        when "trading_retry_training_session" then retry_training_session(params)
        when "trading_delete_training_session" then delete_training_session(params)
        when "trading_training_session_report" then training_session_report(params)
        when "trading_get_strategy_params" then get_strategy_params(params)
        when "trading_update_strategy_params" then update_strategy_params(params)
        when "trading_create_dry_run_session" then create_dry_run_session(params)
        when "trading_seed_strategy_defaults" then seed_strategy_defaults(params)
        when "trading_seed_profit_formula" then seed_profit_formula(params)
        when "trading_import_historical_data" then import_historical_data(params)
        when "trading_run_backtest" then run_backtest(params)
        when "trading_parameter_sweep" then parameter_sweep(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      rescue ActiveRecord::RecordInvalid => e
        error_result(e.message)
      end

      private

      def list_simulations(params)
        portfolio = resolve_portfolio
        scope = portfolio.simulations.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?

        success_result({
          simulations: scope.limit(20).map { |s| serialize_simulation(s) },
          count: scope.count
        })
      end

      def get_simulation(params)
        simulation = resolve_simulation(params[:simulation_id])
        success_result(serialize_simulation(simulation, detailed: true))
      end

      def create_simulation(params)
        portfolio = resolve_portfolio
        strategy = resolve_strategy(params[:strategy_id])
        config = params[:config] || {}

        simulation = portfolio.simulations.create!(
          account_id: account.id,
          name: "Sim: #{strategy.name} #{Time.current.strftime('%Y%m%d_%H%M')}",
          status: "setup",
          total_ticks: config["total_ticks"] || 1000,
          completed_ticks: 0,
          config: config.merge("strategy_id" => strategy.id)
        )

        success_result(serialize_simulation(simulation))
      end

      def run_simulation(params)
        simulation = resolve_simulation(params[:simulation_id])

        unless %w[setup paused].include?(simulation.status)
          return error_result("Simulation cannot be started (status: #{simulation.status})")
        end

        simulation.start! if simulation.status == "setup"

        success_result({
          simulation_id: simulation.id,
          status: simulation.status,
          message: "Simulation started"
        })
      end

      def pause_simulation(params)
        simulation = resolve_simulation(params[:simulation_id])

        unless simulation.status == "running"
          return error_result("Simulation is not running (status: #{simulation.status})")
        end

        simulation.pause!

        success_result({
          simulation_id: simulation.id,
          status: "paused",
          progress_pct: simulation.progress_pct
        })
      end

      def simulation_report(params)
        simulation = resolve_simulation(params[:simulation_id])

        success_result({
          simulation_id: simulation.id,
          name: simulation.name,
          status: simulation.status,
          progress_pct: simulation.progress_pct,
          total_ticks: simulation.total_ticks,
          completed_ticks: simulation.completed_ticks,
          results: simulation.results,
          started_at: simulation.started_at,
          completed_at: simulation.completed_at,
          duration_seconds: simulation.respond_to?(:duration) ? simulation.duration&.to_i : nil
        })
      end

      def list_training_sessions(params)
        scope = Trading::TrainingSession.where(account_id: account.id).order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?

        success_result({
          sessions: scope.limit(20).map { |s| serialize_training_session(s) },
          count: scope.count
        })
      end

      def get_training_session(params)
        session = resolve_training_session(params[:session_id])
        success_result(serialize_training_session(session, detailed: true))
      end

      def create_training_session(params)
        enforce_concurrent_session_limit!

        # Support both nested config and top-level params (top-level takes precedence)
        nested = (params[:config] || {}).stringify_keys
        top_level = params.except(:config, :strategy_id, :action).stringify_keys
        config = nested.merge(top_level.compact)

        incoming_venue = config["venue_slug"]

        # Reject sessions for user-deactivated venues
        if incoming_venue.present?
          venue = Trading::Venue.find_by(slug: incoming_venue)
          return error_result("Venue '#{incoming_venue}' is deactivated") if venue&.config&.dig("user_deactivated")
        end
        incoming_types = config["strategy_types"] || ["llm_probability"]

        # Duplicate detection: check ALL non-terminal sessions with matching venue+types.
        # Uses advisory lock to prevent TOCTOU race where two parallel requests both
        # pass the check before either creates — the H309/H310 duplication pattern.
        #
        # IMPORTANT: Job dispatch must happen AFTER the transaction commits.
        # If we enqueue inside the transaction, the worker picks up the job before
        # the INSERT is visible to other connections → "Training session not found"
        # on the first check_status call (H315/H320/H321 failure pattern).
        if incoming_venue.present?
          lock_key = Zlib.crc32("training_session:#{account.id}:#{incoming_venue}")
          session_to_dispatch = nil
          is_scheduled = config["scheduled_for"].present?
          result = ActiveRecord::Base.transaction do
            ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
            # Scheduled sessions bypass duplicate detection — they coexist since they run at different times
            existing = is_scheduled ? nil : find_existing_training_session(config, incoming_venue, incoming_types)
            if existing
              existing
            else
              session_to_dispatch = create_training_session_record(config)
              success_result(serialize_training_session(session_to_dispatch))
            end
          end
          # Dispatch after transaction commits so the row is visible to the worker.
          # Scheduled sessions are not dispatched — the overseer starts them when scheduled_for arrives.
          if session_to_dispatch && session_to_dispatch.status != "scheduled"
            WorkerJobService.enqueue_trading_training_session(session_to_dispatch.id)
          end
          return result
        end

        create_and_dispatch_training_session(config)
      end

      def cancel_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.status.in?(%w[scheduled pending initializing running paused])
          return error_result("Session is not cancellable in status: #{session.status}")
        end

        session.cancel!
        TradingTrainingChannel.broadcast_cancelled(session)
        success_result(serialize_training_session(session))
      end

      def complete_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.running?
          return error_result("Session can only be completed early when running (current: #{session.status})")
        end

        session.request_completion!
        TradingTrainingChannel.broadcast_completion_requested(session)
        success_result(serialize_training_session(session).merge(completion_requested: true))
      end

      def retry_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.status.in?(%w[failed cancelled])
          return error_result("Only failed or cancelled sessions can be retried")
        end

        has_strategies = session.strategies.any?
        completed = session.completed_ticks || 0

        if has_strategies && completed > 0
          # Resume mode: keep existing strategies, ticks, metrics — pick up where we left off
          session.update!(
            status: "pending",
            error_message: nil,
            completed_at: nil
          )
        else
          # Fresh start: no progress to preserve
          session.update!(
            status: "pending",
            error_message: nil,
            completed_at: nil,
            started_at: nil,
            completed_ticks: 0,
            total_ticks: 0,
            metrics: {},
            results: {},
            timeline: []
          )
        end

        # Reactivate strategies that were decommissioned by cancel/fail
        session.strategies.where(status: "decommissioned").update_all(
          status: "active", lifecycle_phase: "paper_trade"
        )

        # Dispatch immediately to worker — don't wait for the periodic runner poll
        WorkerJobService.enqueue_trading_training_session(session.id)

        success_result(serialize_training_session(session))
      end

      def delete_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.status.in?(%w[pending completed failed cancelled])
          return error_result("Cannot delete a running session. Cancel it first.")
        end

        session.destroy!
        success_result({ deleted: true, id: params[:session_id] })
      end

      def training_session_report(params)
        session = resolve_training_session(params[:session_id])

        unless session.status == "completed" && session.results.present?
          return error_result("Report not available yet")
        end

        success_result(session.results)
      end

      def get_strategy_params(params)
        strategy_type = params[:strategy_type]
        return error_result("strategy_type is required") unless strategy_type.present?

        effective = Trading::StrategyParameterService.params_for(
          strategy_type,
          venue_slug: params[:venue_slug].presence,
          account: account
        )

        # Also show individual layers for transparency
        hardcoded = Trading::LiveTrainingRunner::TRAINING_PARAMETERS.fetch(strategy_type, {})
        global = Trading::StrategyParameterService.read_global_params(account, strategy_type) || {}
        venue = if params[:venue_slug].present?
                  Trading::StrategyParameterService.read_venue_params(account, params[:venue_slug], strategy_type) || {}
                else
                  {}
                end

        success_result({
          strategy_type: strategy_type,
          venue_slug: params[:venue_slug],
          effective: effective,
          layers: {
            hardcoded: hardcoded,
            global_defaults: global,
            venue_overrides: venue
          }
        })
      end

      def update_strategy_params(params)
        strategy_type = params[:strategy_type]
        key = params[:key]
        value = params[:value]
        return error_result("strategy_type and key are required") unless strategy_type.present? && key.present?

        # Validate strategy type exists
        unless Trading::LiveTrainingRunner::TRAINING_PARAMETERS.key?(strategy_type)
          return error_result("Unknown strategy type: #{strategy_type}. Valid types: #{Trading::LiveTrainingRunner::TRAINING_PARAMETERS.keys.join(', ')}")
        end

        Trading::StrategyParameterService.update_param!(
          account: account,
          strategy_type: strategy_type,
          key: key,
          value: value,
          venue_slug: params[:venue_slug].presence
        )

        # Return the updated effective params
        effective = Trading::StrategyParameterService.params_for(
          strategy_type,
          venue_slug: params[:venue_slug].presence,
          account: account
        )

        success_result({
          updated: true,
          strategy_type: strategy_type,
          key: key,
          value: value,
          venue_slug: params[:venue_slug],
          effective: effective
        })
      end

      def create_dry_run_session(params)
        enforce_concurrent_session_limit!

        all_types = Trading::LiveTrainingRunner::TRAINING_PARAMETERS.keys
        venue_slug = params[:venue_slug].presence || "kalshi"
        tick_count = (params[:tick_count] || 5).to_i.clamp(3, 15)

        session = Trading::TrainingSession.create!(
          account_id: account.id,
          name: "Dry Run #{Time.current.strftime('%Y-%m-%d %H:%M')}",
          status: "pending",
          market_count: 2,
          tick_count: tick_count,
          tick_interval: 8,
          strategy_types: all_types,
          include_classic: false,
          config: {
            "venue_slug" => venue_slug,
            "initial_balance" => 10_000.0,
            "mode" => "dry_run",
            "max_markets" => 2,
            "strategy_overrides" => {
              "agent_ensemble" => { "agent_roles" => %w[fundamentals risk_manager], "debate_rounds" => 0, "max_llm_calls_per_tick" => 3 },
              "sentiment_analysis" => { "warm_up_ticks" => 0 }
            }
          }
        )
        WorkerJobService.enqueue_trading_training_session(session.id)
        success_result(serialize_training_session(session))
      end

      def seed_strategy_defaults(_params)
        Trading::StrategyParameterService.seed_defaults!(account: account)

        # Count what was seeded
        strategy_count = Trading::LiveTrainingRunner::TRAINING_PARAMETERS.size
        venue_count = Trading::LiveTrainingRunner::VENUE_CATEGORY_EXCLUSIONS.size +
                      Trading::LiveTrainingRunner::VENUE_STRATEGY_BOOSTS.size

        success_result({
          seeded: true,
          strategy_types: strategy_count,
          venue_configs: venue_count,
          message: "Seeded #{strategy_count} strategy parameter defaults and #{venue_count} venue configs into shared memory"
        })
      end

      def seed_profit_formula(_params)
        Trading::StrategyParameterService.seed_profit_formula!(account: account)

        formula_strategies = %w[
          arbitrage tail_end_yield combinatorial_arbitrage
          longshot_fading prediction_market_making mean_reversion
          momentum cross_platform_arbitrage spot_lag_arbitrage
        ]

        success_result({
          seeded: true,
          strategy_types: formula_strategies,
          layers: {
            "risk_free" => { weight: "40%", strategies: %w[arbitrage tail_end_yield combinatorial_arbitrage] },
            "statistical_edge" => { weight: "40%", strategies: %w[longshot_fading prediction_market_making mean_reversion] },
            "alpha_generation" => { weight: "20%", strategies: %w[momentum cross_platform_arbitrage spot_lag_arbitrage] }
          },
          venue_overrides: %w[kalshi polymarket],
          llm_cost_per_tick: "$0.00",
          message: "Seeded Profit Formula: 9 zero-LLM-cost strategies with venue-specific overrides for Kalshi and Polymarket"
        })
      end

      def import_historical_data(params)
        venue_slug = params[:venue_slug]
        return error_result("venue_slug is required") unless venue_slug.present?

        venue = Trading::Venue.find_by(slug: venue_slug)
        return error_result("Venue '#{venue_slug}' not found") unless venue

        interval = params[:interval].presence || "1h"

        case venue_slug
        when "kalshi"
          importer = Trading::KalshiHistoricalImporter.new(venue)
          ticker = params[:ticker]
          return error_result("ticker is required for Kalshi imports") unless ticker.present?

          # Map interval string to Kalshi period (minutes)
          kalshi_period = case interval
                          when "1m" then 1
                          when "1h" then 60
                          when "1d" then 1440
                          else 60
                          end

          # If ticker looks like an event prefix (e.g., "KXFED"), import the event
          if ticker.length <= 10 && !ticker.include?("/")
            total_imported = importer.import_event(ticker, period: kalshi_period)
            success_result({ venue: venue_slug, event_ticker: ticker, total_imported: total_imported, stats: importer.stats })
          else
            total_imported = importer.import_ticker(ticker, period: kalshi_period)
            success_result({ venue: venue_slug, ticker: ticker, total_imported: total_imported, stats: importer.stats })
          end

        when "polymarket"
          importer = Trading::PolymarketHistoricalImporter.new(venue)
          if params[:slug].present?
            results = importer.import_event(params[:slug], interval: interval)
            success_result({ venue: venue_slug, slug: params[:slug], results: results, total_imported: results.sum { |r| r[:imported] || 0 } })
          elsif params[:ticker].present?
            result = importer.import_condition(params[:ticker], interval: interval)
            success_result({ venue: venue_slug, condition_id: params[:ticker], **result })
          else
            limit = (params[:limit] || 50).to_i
            results = importer.import_from_registry(limit: limit, interval: interval)
            success_result({ venue: venue_slug, source: "registry", results: results, total_imported: results.sum { |r| r[:imported] || 0 } })
          end
        else
          error_result("Historical import not supported for venue '#{venue_slug}'. Supported: kalshi, polymarket")
        end
      end

      def run_backtest(params)
        enforce_concurrent_session_limit!

        profit_formula_types = %w[
          arbitrage tail_end_yield combinatorial_arbitrage
          longshot_fading prediction_market_making mean_reversion
          momentum cross_platform_arbitrage spot_lag_arbitrage
        ]

        strategy_types = params[:strategy_types] || profit_formula_types
        tick_count = (params[:tick_count] || 50).to_i.clamp(5, 500)
        tick_interval = (params[:tick_interval] || 5).to_i.clamp(1, 60)
        initial_balance = (params[:initial_balance] || 10_000).to_f

        # Auto-detect source venue from existing price snapshots so the
        # backtest discovery can find pairs (snapshots are stored with a
        # source like "polymarket_live", not "simulator").
        bt_start = params[:start_at] ? Time.parse(params[:start_at]) : 7.days.ago
        bt_end   = params[:end_at]   ? Time.parse(params[:end_at])   : Time.current
        source_venue = Trading::PriceSnapshot
          .where(timestamp: bt_start..bt_end)
          .where.not(source: "historical")
          .pick(:source)
          &.sub(/_live$/, "") || "polymarket"

        session_config = {
          "venue_slug" => "simulator",
          "source_venue" => source_venue,
          "initial_balance" => initial_balance,
          "price_mode" => "historical_replay",
          "mode" => "backtest",
          "backtest_config" => {
            "start_at" => (params[:start_at] || 7.days.ago.iso8601),
            "end_at" => (params[:end_at] || Time.current.iso8601),
            "replay_interval_hours" => (params[:replay_interval_hours] || 1).to_f
          }
        }
        session_config["strategy_overrides"] = params[:strategy_overrides] if params[:strategy_overrides].present?

        session = Trading::TrainingSession.create!(
          account_id: account.id,
          name: params[:name] || "Backtest #{Time.current.strftime('%Y%m%d_%H%M')}",
          status: "pending",
          market_count: 5,
          tick_count: tick_count,
          tick_interval: tick_interval,
          strategy_types: strategy_types,
          include_classic: false,
          config: session_config
        )

        WorkerJobService.enqueue_trading_training_session(session.id)
        success_result(serialize_training_session(session))
      end

      def parameter_sweep(params)
        strategy_type = params[:strategy_type]
        return error_result("strategy_type is required") unless strategy_type.present?

        # If sweep_id provided, collect existing results
        if params[:sweep_id].present?
          service = Trading::ParameterSweepService.new(
            account: account, strategy_type: strategy_type
          )
          results = service.collect_results(params[:sweep_id])

          if params[:promote_best]
            promoted = service.promote_best!(params[:sweep_id])
            results[:promoted] = promoted
          end

          return success_result(results)
        end

        # Create new sweep
        param_ranges = params[:param_ranges]
        return error_result("param_ranges is required") unless param_ranges.is_a?(Hash) && param_ranges.any?

        max_combos = (params[:max_combos] || 64).to_i.clamp(1, 256)
        method = params[:method].presence || "grid"

        base_config = {
          "venue_slug" => "simulator",
          "initial_balance" => (params[:initial_balance] || 10_000).to_f,
          "tick_count" => (params[:tick_count] || 50).to_i,
          "tick_interval" => 5,
          "price_mode" => "historical_replay"
        }

        service = Trading::ParameterSweepService.new(
          account: account, strategy_type: strategy_type, base_config: base_config
        )

        combinations = service.generate_combinations(param_ranges, method: method, max_combos: max_combos)
        result = service.create_sweep(combinations)

        success_result(result.merge(
          strategy_type: strategy_type,
          method: method,
          combinations_generated: combinations.size,
          message: "Created #{combinations.size} backtest sessions. Use trading_parameter_sweep with sweep_id='#{result[:sweep_id]}' to check results."
        ))
      end

      def enforce_concurrent_session_limit!
        max = Api::V1::Trading::TrainingSessionsController::MAX_CONCURRENT_SESSIONS
        active_count = Trading::TrainingSession
          .where(account_id: account.id, status: %w[pending initializing running paused])
          .count
        return if active_count < max

        raise ArgumentError,
          "Maximum #{max} concurrent training sessions allowed (#{active_count} active). " \
          "Wait for existing sessions to complete, or cancel one before creating another."
      end

      # Check for an existing non-terminal session with matching venue+types.
      # Returns a success_result if found (resuming paused sessions), nil otherwise.
      # Called inside advisory lock transaction.
      def find_existing_training_session(config, venue, types)
        existing = account.trading_training_sessions
          .where(status: %w[pending running paused])
          .where("config->>'venue_slug' = ?", venue)
          .where("strategy_types::jsonb = ?::jsonb", types.to_json)
          .order(created_at: :desc)
          .first

        return nil unless existing

        if existing.status == "paused"
          existing.update!(status: "pending", error_message: "Resumed (duplicate creation prevented)")
          # Safe to enqueue here — the paused session's row already exists and is committed
          WorkerJobService.enqueue_trading_training_session(existing.id)
          return success_result(serialize_training_session(existing).merge("resumed" => true))
        end

        # Pending or running — return it as-is without creating a duplicate
        success_result(serialize_training_session(existing).merge("already_active" => true))
      end

      # Create the session record without dispatching. Caller is responsible
      # for enqueuing the worker job AFTER the transaction commits.
      def create_training_session_record(config)
        session_mode = config["mode"] || "continuous"
        session_config = config.merge(
          "initial_balance" => (config["initial_balance"] || 10_000).to_f,
          "use_performance_sizing" => config["use_performance_sizing"] || false,
          "mode" => session_mode
        )

        scheduled_for = config["scheduled_for"].present? ? Time.parse(config["scheduled_for"]) : nil
        if scheduled_for && scheduled_for < Time.current
          raise ArgumentError, "scheduled_for must be in the future (got #{scheduled_for.iso8601}, current time is #{Time.current.iso8601})"
        end
        session_status = scheduled_for ? "scheduled" : "pending"

        # Compute ends_at from duration_minutes (relative to scheduled_for or now)
        duration = config["duration_minutes"].present? ? config["duration_minutes"].to_i.minutes : nil
        base_time = scheduled_for || Time.current
        ends_at = duration ? base_time + duration : nil

        Trading::TrainingSession.create!(
          account_id: account.id,
          name: config["name"] || "Training #{Time.current.strftime('%Y%m%d_%H%M')}",
          status: session_status,
          mode: session_mode,
          market_count: config["market_count"] || 10,
          tick_count: session_mode == "continuous" ? 0 : (config["tick_count"] || 100),
          tick_interval: config["tick_interval"] || (session_mode == "continuous" ? 15 : 300),
          strategy_types: config["strategy_types"] || ["llm_probability"],
          include_classic: config["include_classic"] || false,
          scheduled_for: scheduled_for,
          ends_at: ends_at,
          config: session_config
        )
      end

      # Create + dispatch for the non-locked path (no venue_slug specified).
      def create_and_dispatch_training_session(config)
        session = create_training_session_record(config)
        WorkerJobService.enqueue_trading_training_session(session.id) unless session.scheduled?
        success_result(serialize_training_session(session))
      end

      def serialize_simulation(simulation, detailed: false)
        data = {
          id: simulation.id,
          name: simulation.name,
          status: simulation.status,
          total_ticks: simulation.total_ticks,
          completed_ticks: simulation.completed_ticks,
          progress_pct: simulation.progress_pct,
          started_at: simulation.started_at,
          completed_at: simulation.completed_at,
          created_at: simulation.created_at
        }

        if detailed
          data[:config] = simulation.config
          data[:results] = simulation.results
        end

        data
      end

      def serialize_training_session(session, detailed: false)
        data = {
          id: session.id,
          name: session.name,
          status: session.status,
          market_count: session.market_count,
          tick_count: session.tick_count,
          strategy_types: session.strategy_types,
          total_ticks: session.total_ticks,
          completed_ticks: session.completed_ticks,
          progress_pct: session.total_ticks.to_i > 0 ?
            (session.completed_ticks.to_f / session.total_ticks * 100).round(1) : 0,
          metrics: session.metrics,
          error_message: session.error_message,
          scheduled_for: session.scheduled_for,
          ends_at: session.ends_at,
          started_at: session.started_at,
          completed_at: session.completed_at,
          created_at: session.created_at
        }

        if detailed
          data[:config] = session.config
          data[:results] = session.results
          data[:tick_interval] = session.tick_interval
          data[:include_classic] = session.include_classic
          data[:initial_balance] = session.config&.dig("initial_balance")&.to_f
        end

        data
      end
    end
  end
end

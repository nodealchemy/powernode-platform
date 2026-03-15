# frozen_string_literal: true

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
              status: { type: "string", required: false, description: "Filter by status: pending, running, completed, failed, cancelled" }
            }
          },
          "trading_get_training_session" => {
            description: "Get training session details including progress and metrics",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
            }
          },
          "trading_create_training_session" => {
            description: "Create a new AI training session. All params can be passed at top level or nested under 'config'.",
            parameters: {
              strategy_id: { type: "string", required: false, description: "Strategy ID or name (optional)" },
              config: { type: "object", required: false, description: "Training session configuration (alternative: pass params at top level)" },
              name: { type: "string", required: false, description: "Session name" },
              strategy_types: { type: "array", required: false, description: "Strategy types to run" },
              market_count: { type: "integer", required: false, description: "Number of markets to discover" },
              tick_count: { type: "integer", required: false, description: "Number of ticks to run" },
              tick_interval: { type: "integer", required: false, description: "Seconds between ticks" },
              initial_balance: { type: "number", required: false, description: "Starting balance in USD" },
              venue_slug: { type: "string", required: false, description: "Trading venue slug (e.g. 'kalshi')" },
              risk_tier: { type: "string", required: false, description: "Risk tier (low/medium/high)" },
              include_classic: { type: "boolean", required: false, description: "Include classic strategies" },
              use_performance_sizing: { type: "boolean", required: false, description: "Enable performance-based position sizing (scales size by win rate)" },
              probability_min: { type: "number", required: false, description: "Min probability filter for market selection" },
              probability_max: { type: "number", required: false, description: "Max probability filter for market selection" },
              min_volume_24h: { type: "number", required: false, description: "Min 24h volume filter" },
              compounding_enabled: { type: "boolean", required: false, description: "Enable profit compounding" },
              compounding_threshold_pct: { type: "number", required: false, description: "P&L threshold % to trigger compounding" },
              compounding_reinvest_pct: { type: "integer", required: false, description: "Percentage of profits to reinvest (0-100)" },
              confidence_threshold: { type: "number", required: false, description: "Minimum confidence score to enter positions" }
            }
          },
          "trading_cancel_training_session" => {
            description: "Cancel a running or pending training session",
            parameters: {
              session_id: { type: "string", required: true, description: "Training session ID" }
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
              value: { required: true, description: "New value for the parameter" },
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
        when "trading_retry_training_session" then retry_training_session(params)
        when "trading_delete_training_session" then delete_training_session(params)
        when "trading_training_session_report" then training_session_report(params)
        when "trading_get_strategy_params" then get_strategy_params(params)
        when "trading_update_strategy_params" then update_strategy_params(params)
        when "trading_create_dry_run_session" then create_dry_run_session(params)
        when "trading_seed_strategy_defaults" then seed_strategy_defaults(params)
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

        session_config = config.merge(
          "initial_balance" => (config["initial_balance"] || 10_000).to_f,
          "use_performance_sizing" => config["use_performance_sizing"] || false
        )

        session = Trading::TrainingSession.create!(
          account_id: account.id,
          name: config["name"] || "Training #{Time.current.strftime('%Y%m%d_%H%M')}",
          status: "pending",
          market_count: config["market_count"] || 10,
          tick_count: config["tick_count"] || 100,
          tick_interval: config["tick_interval"] || 300,
          strategy_types: config["strategy_types"] || ["llm_probability"],
          include_classic: config["include_classic"] || false,
          config: session_config
        )

        # Dispatch immediately to worker — don't wait for the periodic runner poll
        WorkerJobService.enqueue_trading_training_session(session.id)

        success_result(serialize_training_session(session))
      end

      def cancel_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.status.in?(%w[scheduled pending running paused])
          return error_result("Session is not cancellable in status: #{session.status}")
        end

        session.cancel!
        success_result(serialize_training_session(session))
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

      def enforce_concurrent_session_limit!
        max = Api::V1::Trading::TrainingSessionsController::MAX_CONCURRENT_SESSIONS
        active_count = Trading::TrainingSession
          .where(account_id: account.id, status: %w[pending running paused])
          .count
        return if active_count < max

        raise ArgumentError,
          "Maximum #{max} concurrent training sessions allowed (#{active_count} active). " \
          "Wait for existing sessions to complete, or cancel one before creating another."
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

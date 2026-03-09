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
            description: "Create a new AI training session",
            parameters: {
              strategy_id: { type: "string", required: false, description: "Strategy ID or name (optional)" },
              config: { type: "object", required: false, description: "Training session configuration" }
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
        config = params[:config] || {}
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

        success_result(serialize_training_session(session))
      end

      def cancel_training_session(params)
        session = resolve_training_session(params[:session_id])

        unless session.status.in?(%w[pending running])
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

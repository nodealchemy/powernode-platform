# frozen_string_literal: true

module Ai
  module Tools
    class TradingEvolutionTool < BaseTool
      include Concerns::TradingContextResolvable

      REQUIRED_PERMISSION = "trading.view"

      def self.definition
        {
          name: "trading_evolution_management",
          description: "Query evolution epochs, leaderboards, and trading audit logs",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            epoch_id: { type: "string", required: false, description: "Evolution epoch ID" },
            config: { type: "object", required: false, description: "Evolution configuration" },
            action_type: { type: "string", required: false, description: "Filter audit logs by action type" },
            limit: { type: "integer", required: false, description: "Max results to return" }
          }
        }
      end

      def self.action_definitions
        {
          "trading_list_evolution_epochs" => {
            description: "List evolution epochs with fitness statistics",
            parameters: {
              limit: { type: "integer", required: false, description: "Max results (default: 10)" }
            }
          },
          "trading_get_evolution_epoch" => {
            description: "Get epoch details with candidate count and fitness stats",
            parameters: {
              epoch_id: { type: "string", required: true, description: "Evolution epoch ID" }
            }
          },
          "trading_evolution_leaderboard" => {
            description: "Get ranked candidate strategies for an evolution epoch",
            parameters: {
              epoch_id: { type: "string", required: true, description: "Evolution epoch ID" }
            }
          },
          "trading_trigger_evolution" => {
            description: "Trigger a new evolution epoch for strategy optimization",
            parameters: {
              config: { type: "object", required: false, description: "Evolution configuration" }
            }
          },
          "trading_list_audit_logs" => {
            description: "List trading audit log entries",
            parameters: {
              action_type: { type: "string", required: false, description: "Filter by action type" },
              limit: { type: "integer", required: false, description: "Max results (default: 20)" }
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
        when "trading_list_evolution_epochs" then list_evolution_epochs(params)
        when "trading_get_evolution_epoch" then get_evolution_epoch(params)
        when "trading_evolution_leaderboard" then evolution_leaderboard(params)
        when "trading_trigger_evolution" then trigger_evolution(params)
        when "trading_list_audit_logs" then list_audit_logs(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      rescue ActiveRecord::RecordNotFound => e
        error_result(e.message)
      end

      private

      def list_evolution_epochs(params)
        portfolio = resolve_portfolio
        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        epochs = portfolio.evolution_epochs.order(epoch_number: :desc).limit(limit)

        success_result({
          epochs: epochs.map { |e| serialize_epoch(e) },
          count: portfolio.evolution_epochs.count
        })
      end

      def get_evolution_epoch(params)
        epoch = resolve_epoch(params[:epoch_id])

        data = serialize_epoch(epoch)
        data[:results] = epoch.results
        data[:candidates_count] = epoch.candidates.count
        data[:top_fitness] = epoch.candidates.maximum(:fitness_score)&.to_f
        data[:avg_fitness] = epoch.candidates.average(:fitness_score)&.to_f

        success_result(data)
      end

      def evolution_leaderboard(params)
        epoch = resolve_epoch(params[:epoch_id])
        candidates = epoch.candidates.order(fitness_score: :desc).limit(20)

        success_result({
          epoch_id: epoch.id,
          epoch_number: epoch.epoch_number,
          candidates: candidates.map do |c|
            breakdown = c.fitness_breakdown || {}
            {
              id: c.id,
              strategy_id: c.trading_strategy_id,
              strategy_name: c.strategy&.name,
              rank: c.rank,
              fitness_score: c.fitness_score.to_f,
              action_taken: c.action_taken,
              sharpe_ratio: breakdown["sharpe_ratio"]&.to_f,
              sortino_ratio: breakdown["sortino_ratio"]&.to_f,
              max_drawdown_pct: breakdown["max_drawdown_pct"]&.to_f,
              win_rate: breakdown["win_rate"]&.to_f,
              profit_factor: breakdown["profit_factor"]&.to_f,
              pnl_usd: breakdown["pnl_usd"]&.to_f
            }
          end
        })
      end

      def trigger_evolution(params)
        portfolio = resolve_portfolio
        config = params[:config] || {}

        last_epoch = portfolio.evolution_epochs.order(epoch_number: :desc).first
        next_number = (last_epoch&.epoch_number || 0) + 1

        epoch = portfolio.evolution_epochs.create!(
          epoch_number: next_number,
          status: "pending",
          strategies_evaluated: 0,
          fitness_weights: config["fitness_weights"] || Trading::EvolutionEpoch::DEFAULT_FITNESS_WEIGHTS
        )

        success_result({
          epoch_id: epoch.id,
          epoch_number: epoch.epoch_number,
          status: "pending",
          message: "Evolution epoch #{next_number} created"
        })
      end

      def list_audit_logs(params)
        limit = (params[:limit] || 20).to_i.clamp(1, 100)
        scope = Trading::AuditLog.where(account_id: account.id).order(created_at: :desc)
        scope = scope.where(action: params[:action_type]) if params[:action_type].present?

        success_result({
          logs: scope.limit(limit).map do |log|
            {
              id: log.id,
              action: log.action,
              auditable_type: log.auditable_type,
              auditable_id: log.auditable_id,
              metadata: log.metadata,
              created_at: log.created_at
            }
          end,
          count: scope.count
        })
      end

      def serialize_epoch(epoch)
        {
          id: epoch.id,
          epoch_number: epoch.epoch_number,
          status: epoch.status,
          strategies_evaluated: epoch.strategies_evaluated,
          started_at: epoch.started_at,
          completed_at: epoch.completed_at
        }
      end
    end
  end
end

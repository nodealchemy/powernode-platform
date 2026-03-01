# frozen_string_literal: true

module Ai
  module Autonomy
    class BudgetAwareContextService
      REGIMES = {
        "NORMAL" => { threshold: 0.0, max: 0.5, message: "Budget availability is healthy. Full operations permitted." },
        "CAUTIOUS" => { threshold: 0.5, max: 0.8, message: "Budget is moderate. Balance quality with cost." },
        "CRITICAL" => { threshold: 0.8, max: 1.0, message: "Budget is critically low. Only essential operations permitted." },
        "EXHAUSTED" => { threshold: 1.0, max: Float::INFINITY, message: "Budget is exhausted. New executions blocked." }
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Generate budget-aware context for system prompt injection
      # @param agent [Ai::Agent] The agent
      # @return [Hash] { regime: String, context: String, utilization_pct: Float, remaining_cents: Integer }
      def generate_context(agent:)
        budget = ::Ai::AgentBudget.where(agent_id: agent.id, account_id: account.id).active.first
        return no_budget_context unless budget

        utilization = budget.utilization_percentage / 100.0
        regime = determine_regime(utilization)
        velocity = check_rate_of_change(agent, budget)

        context_lines = [
          "[BUDGET STATUS: #{regime[:level]}]",
          "Remaining: #{budget.remaining_cents} cents (#{((1 - utilization) * 100).round(1)}%)",
          regime[:message]
        ]

        context_lines << "WARNING: Spend velocity is #{velocity[:rate]}x expected pace." if velocity[:alert]

        {
          regime: regime[:level],
          context: context_lines.join("\n"),
          utilization_pct: (utilization * 100).round(2),
          remaining_cents: budget.remaining_cents,
          velocity_alert: velocity[:alert],
          velocity_rate: velocity[:rate]
        }
      end

      # Check spending velocity
      # @param agent [Ai::Agent] The agent
      # @param budget [Ai::AgentBudget] The budget
      # @return [Hash] { alert: Boolean, rate: Float }
      def check_rate_of_change(agent, budget)
        return { alert: false, rate: 1.0 } unless budget.period_start && budget.period_end

        total_period = budget.period_end - budget.period_start
        elapsed = Time.current - budget.period_start
        return { alert: false, rate: 1.0 } if total_period <= 0 || elapsed <= 0

        time_pct = elapsed / total_period
        spend_pct = budget.utilization_percentage / 100.0

        rate = time_pct.positive? ? (spend_pct / time_pct).round(2) : 0.0
        { alert: rate > 2.0, rate: rate }
      end

      private

      def determine_regime(utilization)
        REGIMES.each do |level, config|
          if utilization >= config[:threshold] && utilization < config[:max]
            return { level: level, message: config[:message] }
          end
        end
        { level: "CRITICAL", message: REGIMES["CRITICAL"][:message] }
      end

      def no_budget_context
        {
          regime: "NONE",
          context: "[NO BUDGET CONFIGURED]",
          utilization_pct: 0.0,
          remaining_cents: 0,
          velocity_alert: false,
          velocity_rate: 0.0
        }
      end
    end
  end
end

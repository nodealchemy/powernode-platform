# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class BudgetSensor < Base
        LOW_BUDGET_THRESHOLD = 0.2  # 20% remaining
        BURN_RATE_WINDOW = 24.hours

        def sensor_type
          "budget"
        end

        def collect
          observations = []

          budget = Ai::AgentBudget.where(agent_id: agent.id).active.first
          return observations unless budget

          utilization = budget.utilization_percentage / 100.0

          # Check low budget
          if utilization > (1 - LOW_BUDGET_THRESHOLD)
            remaining_pct = ((1 - utilization) * 100).round(1)
            obs = build_observation(
              title: "Budget #{remaining_pct}% remaining (#{budget.remaining_cents}¢)",
              observation_type: "alert",
              severity: remaining_pct < 5 ? "critical" : "warning",
              data: {
                remaining_cents: budget.remaining_cents,
                allocated_cents: budget.allocated_cents,
                utilization_pct: (utilization * 100).round(1)
              },
              requires_action: remaining_pct < 5,
              expires_in: 2.hours
            )
            observations << obs if obs
          end

          # Check burn rate velocity
          burn_rate = calculate_burn_rate(budget)
          if burn_rate.present? && budget.remaining_cents > 0
            hours_remaining = budget.remaining_cents / burn_rate
            if hours_remaining < 4
              obs = build_observation(
                title: "Budget will exhaust in ~#{hours_remaining.round(1)} hours at current rate",
                observation_type: "alert",
                severity: "warning",
                data: {
                  burn_rate_per_hour: burn_rate.round(2),
                  estimated_hours_remaining: hours_remaining.round(1)
                },
                requires_action: true,
                expires_in: 1.hour
              )
              observations << obs if obs
            end
          end

          observations.compact
        end

        private

        def calculate_burn_rate(budget)
          recent_spend = Ai::AgentExecution
            .where(ai_agent_id: agent.id)
            .where("created_at >= ?", BURN_RATE_WINDOW.ago)
            .sum(:cost_cents)

          return nil if recent_spend == 0

          recent_spend.to_f / (BURN_RATE_WINDOW / 1.hour)
        rescue StandardError
          nil
        end
      end
    end
  end
end

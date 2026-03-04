# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class GoalProgressSensor < Base
        STALE_HOURS = 24

        def collect
          observations = []

          # Check for stale goals (no progress in 24h)
          stale_goals = Ai::AgentGoal.where(ai_agent_id: agent.id, status: "active")
            .where("updated_at < ?", STALE_HOURS.hours.ago)

          stale_goals.each do |goal|
            observations << build_observation(
              sensor_type: "goal_progress",
              observation_type: "degradation",
              severity: "warning",
              title: "Goal '#{goal.title}' has no progress for #{STALE_HOURS}h",
              data: {
                goal_id: goal.id,
                goal_title: goal.title,
                last_updated: goal.updated_at.iso8601,
                progress: goal.progress,
                fingerprint: "stale_goal_#{goal.id}"
              },
              requires_action: true,
              expires_at: 12.hours.from_now
            )
          end

          # Check for stuck plan steps
          stuck_steps = Ai::GoalPlanStep.joins(:plan)
            .where(ai_goal_plans: { ai_agent_id: agent.id })
            .where(status: "executing")
            .where("ai_goal_plan_steps.started_at < ?", 2.hours.ago)

          stuck_steps.each do |step|
            observations << build_observation(
              sensor_type: "goal_progress",
              observation_type: "anomaly",
              severity: "warning",
              title: "Plan step ##{step.step_number} stuck for >2h",
              data: {
                step_id: step.id,
                plan_id: step.plan_id,
                step_type: step.step_type,
                started_at: step.started_at.iso8601,
                fingerprint: "stuck_step_#{step.id}"
              },
              requires_action: true,
              expires_at: 6.hours.from_now
            )
          end

          # Check for budget overrun on active plans
          Ai::GoalPlan.where(ai_agent_id: agent.id, status: "executing").each do |plan|
            budget = Ai::AgentBudget.where(agent_id: agent.id).active.first
            next unless budget && plan.estimated_cost_usd

            if budget.remaining_cents < (plan.estimated_cost_usd * 100 * 0.5)
              observations << build_observation(
                sensor_type: "goal_progress",
                observation_type: "alert",
                severity: "critical",
                title: "Budget may be insufficient for plan completion",
                data: {
                  plan_id: plan.id,
                  estimated_cost: plan.estimated_cost_usd,
                  remaining_budget: budget.remaining_cents / 100.0,
                  fingerprint: "budget_overrun_#{plan.id}"
                },
                requires_action: true,
                expires_at: 4.hours.from_now
              )
            end
          end

          observations
        end
      end
    end
  end
end

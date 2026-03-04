# frozen_string_literal: true

module Ai
  module Autonomy
    class GoalDrivenSchedulerService
      # Trust-based auto-approval thresholds (USD)
      TRUST_THRESHOLDS = {
        "supervised" => 0,
        "monitored" => 1.0,
        "trusted" => 5.0,
        "autonomous" => Float::INFINITY
      }.freeze

      def initialize(account:, agent:)
        @account = account
        @agent = agent
        @actions_yielded = 0
      end

      def select_next_goal
        goals = Ai::AgentGoal.where(ai_agent_id: @agent.id, status: "active").by_priority

        goals.max_by do |goal|
          priority_score = goal.priority.to_f
          deadline_proximity = goal.respond_to?(:deadline) && goal.deadline ? [1.0 / [(goal.deadline - Time.current).to_f / 1.day, 0.1].max, 2.0].min : 0.0
          budget_ok = has_budget? ? 1.0 : 0.0

          priority_score * 0.4 + deadline_proximity * 0.3 + budget_ok * 0.3
        end
      end

      def should_execute_now?
        return false unless has_budget?
        return false if kill_switch_active?
        return false if duty_cycle_exceeded?
        return false unless has_active_goals?

        true
      end

      def next_action
        return nil unless should_execute_now?
        return nil if @actions_yielded >= 5 # Safety limit

        @actions_yielded += 1
        goal = select_next_goal
        return nil unless goal

        # Check if goal needs a plan
        current_plan = goal.respond_to?(:plans) ? goal.plans&.active&.by_version&.first : nil
        current_plan ||= Ai::GoalPlan.for_goal(goal.id).active.by_version.first

        unless current_plan
          return { type: :decompose, goal_id: goal.id }
        end

        case current_plan.status
        when "draft"
          { type: :validate, plan_id: current_plan.id, goal_id: goal.id }
        when "validated"
          if can_auto_approve?(current_plan)
            current_plan.approve!(user: nil) # Auto-approve
            { type: :execute_step, plan_id: current_plan.id, step_id: current_plan.next_executable_step&.id, goal_id: goal.id }
          else
            nil # Needs human approval
          end
        when "approved", "executing"
          step = current_plan.next_executable_step
          if step&.dependencies_met?
            { type: :execute_step, plan_id: current_plan.id, step_id: step.id, goal_id: goal.id }
          elsif current_plan.all_steps_completed?
            { type: :evaluate_plan, plan_id: current_plan.id, goal_id: goal.id }
          else
            nil
          end
        when "failed"
          { type: :decompose, goal_id: goal.id } # Trigger replan
        else
          nil
        end
      end

      private

      def has_budget?
        budget = Ai::AgentBudget.where(agent_id: @agent.id).active.first
        budget.nil? || budget.remaining_cents > 0
      end

      def kill_switch_active?
        Ai::KillSwitchEvent.where(account_id: @account.id, status: "active").exists?
      end

      def duty_cycle_exceeded?
        Ai::Autonomy::DutyCycleService.new(account: @account, agent: @agent).exceeded?
      rescue StandardError
        false
      end

      def has_active_goals?
        Ai::AgentGoal.where(ai_agent_id: @agent.id, status: "active").exists?
      end

      def can_auto_approve?(plan)
        trust_score = Ai::AgentTrustScore.find_by(agent_id: plan.ai_agent_id)
        tier = trust_score&.tier || "supervised"
        threshold = TRUST_THRESHOLDS[tier] || 0

        return false if threshold.zero? # Supervised agents can't auto-approve

        estimated_cost = plan.estimated_cost_usd || 0
        estimated_cost <= threshold
      end
    end
  end
end

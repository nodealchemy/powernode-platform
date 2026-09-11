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
        refusal_reason.nil?
      end

      # WHY THIS AGENT MAY NOT ACT NOW, or nil when it may. The one definition
      # of the gates every scheduled paid action passes. Self-correct's replan
      # asks this same question instead of keeping its own copy (goal-plan
      # ruling 3).
      def refusal_reason
        return :no_budget unless has_budget?
        return :halted if kill_switch_active?
        return :duty_cycle if duty_cycle_exceeded?
        return :no_active_goals unless has_active_goals?

        nil
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
          # A goal whose latest plan FAILED is not decomposed here. That would
          # be a paid replan outside the one replan door, self-correct, which
          # classifies the failure, bounds the attempts and runs the gates
          # (goal-plan ruling 3). Without this, concluding a plan as failed
          # re-decomposed its goal on every cycle. A goal that never had a
          # plan, or whose latest plan was rejected, is still decomposed.
          latest = Ai::GoalPlan.for_goal(goal.id).by_version.first
          return nil if latest&.status == "failed"

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
          # A step behind a failed dependency can never run. Skipping it is
          # what lets a plan with a failed step reach `concludable?` instead of
          # sitting in executing with nothing able to move it (goal-plan
          # ruling 1). `concludable?` covers every step completed AND every
          # step terminal with a failure; `evaluate_plan_completion` tells the
          # two apart.
          current_plan.skip_unreachable_steps!
          step = current_plan.next_executable_step
          if step&.dependencies_met?
            { type: :execute_step, plan_id: current_plan.id, step_id: step.id, goal_id: goal.id }
          elsif current_plan.concludable?
            { type: :evaluate_plan, plan_id: current_plan.id, goal_id: goal.id }
          else
            nil
          end
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
        # The canonical halt signal is account.ai_suspended? (set by
        # KillSwitchService#emergency_halt!). Ai::KillSwitchEvent is an audit
        # log of halt/resume events — it has no "active"/"status" column, so a
        # status-based query here is a silent no-op. Always go through the service.
        Ai::Autonomy::KillSwitchService.new(account: @account).halted?
      end

      def duty_cycle_exceeded?
        Ai::Autonomy::DutyCycleService.daily_limit_exceeded?(@agent)
      rescue StandardError => e
        Rails.logger.warn("[GoalDrivenScheduler] duty-cycle budget check failed for agent #{@agent.id}: #{e.message}")
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

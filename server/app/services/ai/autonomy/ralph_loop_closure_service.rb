# frozen_string_literal: true

module Ai
  module Autonomy
    class RalphLoopClosureService
      # ── SELF-CORRECT IS THE ONE REPLAN DOOR (goal-plan rulings 2 and 3) ─────
      # A replan is a paid model call (GoalDecompositionService#decompose). It
      # used to run here for every failed plan of the agent on every cycle for
      # 24 hours, outside every gate the scheduler applies. Now a failed plan
      # is replanned only when all of these hold, checked in this order:
      #   1. its goal is still active;
      #   2. its failure is TRANSIENT (`Ai::GoalPlanStep::FAILURE_KINDS`). A
      #      deterministic or unclassified failure fails the same way on every
      #      replan, so replanning it only spends money;
      #   3. the goal has made fewer than `max_replans_per_goal` paid replan
      #      attempts. At the bound the goal fails, naming the setting;
      #   4. the scheduler's gates are open: budget, kill switch, duty cycle
      #      (`GoalDrivenSchedulerService#refusal_reason`);
      #   5. the capability matrix ALLOWS `plan_and_execute` for the agent's
      #      tier, so a supervised agent is never auto-replanned.
      # Decisions 1-3, and a replan that produced a plan, are FINAL: the plan
      # is not looked at again. Gates 4-5 can open without anything being
      # spent, so a plan they refused is re-checked on the next cycle.
      MAX_REPLANS_SETTING = "ai.autonomy.max_replans_per_goal"
      DEFAULT_MAX_REPLANS_PER_GOAL = 2
      REPLAN_ACTION = "plan_and_execute"
      REPLANS_ATTEMPTED_KEY = "replans_attempted"
      SELF_CORRECT_KEY = "self_correct"
      FINAL_DECISIONS = %i[goal_not_active deterministic bound_reached replanned].freeze

      # Paid replan attempts allowed per goal over its lifetime. A blank or
      # non-positive setting falls back to the named default.
      def self.max_replans_per_goal
        configured = ::SiteSetting.get(MAX_REPLANS_SETTING)
        configured.present? && configured.to_i.positive? ? configured.to_i : DEFAULT_MAX_REPLANS_PER_GOAL
      end

      def initialize(account:, agent:)
        @account = account
        @agent = agent
      end

      # Full OODA+Learn cycle
      def execute_cycle
        results = { observe: 0, orient: [], decide: [], act: [], learn: 0, self_correct: 0 }

        # 1. Observe: Run sensors
        pipeline = ObservationPipelineService.new(account: @account, agent: @agent)
        observations = pipeline.run
        results[:observe] = observations.size

        # 2. Orient: Match observations to goals
        active_goals = Ai::AgentGoal.where(ai_agent_id: @agent.id, status: "active").by_priority
        observations.each do |obs|
          matched_goal = match_observation_to_goal(obs, active_goals)
          results[:orient] << { observation_id: obs.id, goal_id: matched_goal&.id }
        end

        # 3. Decide: Update/create goals, trigger decomposition
        scheduler = GoalDrivenSchedulerService.new(account: @account, agent: @agent)
        while (action = scheduler.next_action)
          results[:decide] << action

          # 4. Act: Execute based on decision
          case action[:type]
          when :decompose
            goal = Ai::AgentGoal.find_by(id: action[:goal_id])
            if goal
              decomposer = GoalDecompositionService.new(account: @account)
              decomposer.decompose(goal)
            end
          when :validate
            plan = Ai::GoalPlan.find_by(id: action[:plan_id])
            if plan
              decomposer = GoalDecompositionService.new(account: @account)
              decomposer.validate(plan)
            end
          when :execute_step
            step = Ai::GoalPlanStep.find_by(id: action[:step_id])
            execute_plan_step(step) if step
          when :evaluate_plan
            plan = Ai::GoalPlan.find_by(id: action[:plan_id])
            evaluate_plan_completion(plan) if plan
          end

          results[:act] << action
          break if results[:decide].size >= 5 # Safety limit per cycle
        end

        # 5. Learn: Extract learnings from cycle
        begin
          learning_service = Ai::Learning::CompoundLearningService.new(account: @account)
          recent_execs = Ai::AgentExecution.where(ai_agent_id: @agent.id)
            .where("created_at >= ?", 1.hour.ago)
          recent_execs.each do |exec|
            learning_service.post_execution_extract(exec)
            results[:learn] += 1
          end
        rescue StandardError => e
          Rails.logger.warn("[RalphLoopClosure] Learning extraction failed: #{e.message}")
        end

        # 6. Self-Correct: the one replan door (see the class header)
        results[:self_correct] = self_correct

        Rails.logger.info("[RalphLoopClosure] Cycle complete: #{results.inspect}")
        results
      rescue StandardError => e
        Rails.logger.error("[RalphLoopClosure] Cycle failed: #{e.message}")
        results
      end

      private

      def match_observation_to_goal(observation, goals)
        # Simple keyword matching between observation title/data and goal title/description
        goals.find do |goal|
          goal_text = "#{goal.title} #{goal.description}".downcase
          obs_text = "#{observation.title} #{observation.data.to_json}".downcase

          # Check for keyword overlap
          goal_words = goal_text.split(/\s+/).select { |w| w.length > 3 }.uniq
          obs_words = obs_text.split(/\s+/).select { |w| w.length > 3 }.uniq
          (goal_words & obs_words).size >= 2
        end
      end

      def execute_plan_step(step)
        step.start!

        case step.step_type
        when "agent_execution"
          # Enqueue execution via worker
          WorkerJobService.enqueue_ai_goal_plan_step_execution(step.id)
        when "observation"
          # Just mark as completed — observations are passive
          step.complete!(result: "Observation checkpoint passed")
        when "human_review"
          # Leave pending for human
          Rails.logger.info("[RalphLoopClosure] Step #{step.id} requires human review")
        when "sub_goal"
          # Sub-goal will be managed by its own plan
          step.complete!(result: "Sub-goal created") if step.sub_goal_id.present?
        end
      rescue StandardError => e
        step.fail!(reason: e.message, kind: "dispatch_raised")
        Rails.logger.warn("[RalphLoopClosure] Step execution failed: #{e.message}")
      end

      # CONCLUDE A PLAN NOTHING CAN MOVE (goal-plan ruling 1). A plan with a
      # failure concludes as failed with the failing step's own reason and
      # class, not "One or more steps failed".
      def evaluate_plan_completion(plan)
        if plan.all_steps_completed?
          plan.complete!
          plan.goal.update!(status: "achieved", progress: 1.0)
        elsif plan.concludable? && (failed = plan.first_failed_step)
          reason = failed.result_summary.presence || "step #{failed.step_number} failed"
          plan.fail!(reason: reason, failure_class: failed.failure_class)
          return if failed.failure_class == Ai::GoalPlanStep::FAILURE_TRANSIENT

          # No replan can change a deterministic failure, so the goal ends with
          # it (ruling 2), and neither the scheduler nor self-correct picks the
          # goal up again.
          plan.goal.fail!("plan v#{plan.version} failed: #{reason}")
        end
      end

      def self_correct
        replanned = 0
        Ai::GoalPlan.where(ai_agent_id: @agent.id, status: "failed")
                    .where("updated_at >= ?", 24.hours.ago)
                    .where("(validation_result -> '#{SELF_CORRECT_KEY}' ->> 'final') IS DISTINCT FROM 'true'")
                    .includes(:goal)
                    .find_each do |plan|
          decision, reason = replan_decision(plan)
          if decision == :replan
            replanned += 1 if replan!(plan)
          else
            record_self_correct(plan, decision: decision, reason: reason, final: FINAL_DECISIONS.include?(decision))
          end
        end
        replanned
      end

      # [decision, reason], checked in the order the class header gives.
      def replan_decision(plan)
        goal = plan.goal
        return [ :goal_not_active, "goal is #{goal&.status || 'missing'}" ] unless goal&.status == "active"

        failure_class = plan.validation_result.to_h["failure_class"].presence || Ai::GoalPlanStep::FAILURE_DETERMINISTIC
        unless failure_class == Ai::GoalPlanStep::FAILURE_TRANSIENT
          return [ :deterministic, "the failure is #{failure_class}, so a replan would fail the same way" ]
        end

        bound = self.class.max_replans_per_goal
        if goal.metadata.to_h[REPLANS_ATTEMPTED_KEY].to_i >= bound
          reason = "replan limit reached: #{bound} paid replan attempts (#{MAX_REPLANS_SETTING})"
          goal.fail!(reason)
          return [ :bound_reached, reason ]
        end

        gate = GoalDrivenSchedulerService.new(account: @account, agent: @agent).refusal_reason
        return [ :"gate_#{gate}", "a scheduler gate is closed: #{gate}" ] if gate

        policy = CapabilityMatrixService.new(account: @account).check(agent: @agent, action_type: REPLAN_ACTION)
        return [ :capability, "the capability matrix answers #{policy} for #{REPLAN_ACTION}" ] unless policy == :allowed

        [ :replan, nil ]
      end

      # The attempt is counted BEFORE the call. An attempt that raises or
      # yields no plan has still been paid for, and the bound is on paid
      # attempts.
      def replan!(plan)
        goal = plan.goal
        attempt = goal.metadata.to_h[REPLANS_ATTEMPTED_KEY].to_i + 1
        goal.update!(metadata: goal.metadata.to_h.merge(REPLANS_ATTEMPTED_KEY => attempt))

        new_plan = GoalDecompositionService.new(account: @account).replan(goal, failed_plan: plan)
        if new_plan
          record_self_correct(plan, decision: :replanned, reason: "replan attempt #{attempt}", final: true,
                                    new_plan_id: new_plan.id)
        else
          # Nothing came back. Not final: the next cycle may try again, and
          # the attempt counter bounds how often.
          record_self_correct(plan, decision: :replan_produced_no_plan,
                                    reason: "replan attempt #{attempt} produced no plan", final: false)
        end
        new_plan
      end

      # `update_columns`, so recording a decision does not touch `updated_at`,
      # which anchors the 24-hour selection window to the failure.
      def record_self_correct(plan, decision:, reason:, final:, new_plan_id: nil)
        entry = { "decision" => decision.to_s, "reason" => reason, "final" => final,
                  "decided_at" => Time.current.utc.iso8601, "new_plan_id" => new_plan_id }.compact
        plan.update_columns(validation_result: plan.validation_result.to_h.merge(SELF_CORRECT_KEY => entry))
      end
    end
  end
end

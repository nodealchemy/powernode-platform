# frozen_string_literal: true

module Ai
  module Autonomy
    class RalphLoopClosureService
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
          break if results[:decide].size >= 5 # Safety limit per cycle

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

        # 6. Self-Correct: Replan failed goals
        failed_plans = Ai::GoalPlan.where(ai_agent_id: @agent.id, status: "failed")
          .where("updated_at >= ?", 24.hours.ago)
        failed_plans.each do |plan|
          decomposer = GoalDecompositionService.new(account: @account)
          decomposer.replan(plan.goal, failed_plan: plan)
          results[:self_correct] += 1
        end

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
        when "workflow_run"
          config = step.execution_config
          if config["workflow_id"]
            WorkerJobService.enqueue_ai_workflow_execution(config["workflow_id"], config)
          end
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
        step.fail!(reason: e.message)
        Rails.logger.warn("[RalphLoopClosure] Step execution failed: #{e.message}")
      end

      def evaluate_plan_completion(plan)
        if plan.all_steps_completed?
          plan.complete!
          plan.goal.update!(status: "achieved", progress: 1.0)
        elsif plan.steps.where(status: "failed").any?
          plan.fail!(reason: "One or more steps failed")
        end
      end
    end
  end
end

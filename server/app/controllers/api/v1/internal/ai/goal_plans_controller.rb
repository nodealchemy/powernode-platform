# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class GoalPlansController < InternalBaseController
          # POST /api/v1/internal/ai/goal_plans/execute_step
          # Called by AiGoalPlanExecutionJob to advance a goal plan step
          def execute_step
            step = ::Ai::GoalPlanStep.find(params[:step_id])
            plan = step.goal_plan

            unless step.dependencies_met?
              return render_error("Step dependencies not met", status: :unprocessable_content)
            end

            step.start!

            begin
              result = dispatch_step(step)
              step.complete!(result: result)
            rescue StandardError => e
              step.fail!(reason: e.message)
              Rails.logger.error "[GoalPlan] Step #{step.id} failed: #{e.message}"
              return render_success(
                step_id: step.id,
                status: "failed",
                reason: e.message,
                plan_progress: plan.progress_percentage
              )
            end

            # Check if the whole plan is now complete
            plan.complete! if plan.all_steps_completed?

            render_success(
              step_id: step.id,
              status: "completed",
              plan_progress: plan.progress_percentage,
              plan_completed: plan.all_steps_completed?
            )
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          end

          private

          def dispatch_step(step)
            case step.step_type
            when "execute_agent"
              dispatch_agent_step(step)
            when "api_call"
              dispatch_api_call_step(step)
            when "decompose"
              dispatch_decompose_step(step)
            else
              "Completed step type: #{step.step_type}"
            end
          end

          def dispatch_agent_step(step)
            config = step.config || {}
            agent = ::Ai::Agent.find(config["agent_id"] || step.goal_plan.agent_goal.ai_agent_id)
            execution = agent.executions.create!(
              account: step.goal_plan.account,
              prompt: config["prompt"] || step.description,
              status: "pending"
            )
            "Agent execution #{execution.id} created"
          end

          def dispatch_api_call_step(step)
            "API call step acknowledged"
          end

          def dispatch_decompose_step(step)
            goal = step.goal_plan.agent_goal
            service = ::Ai::Autonomy::GoalDecompositionService.new(account: step.goal_plan.account)
            sub_plan = service.decompose(goal: goal)
            "Decomposed into #{sub_plan&.steps&.count || 0} sub-steps"
          end
        end
      end
    end
  end
end

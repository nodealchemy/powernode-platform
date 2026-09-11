# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class GoalPlansController < InternalBaseController
          # POST /api/v1/internal/ai/goal_plans/execute_step
          # Called by AiGoalPlanExecutionJob, which RalphLoopClosureService
          # enqueues for agent_execution steps.
          #
          # NO STEP TYPE HAS A DISPATCHER HERE (goal_plans ruling, option A).
          # This used to crash at `step.goal_plan` (the association is `plan`)
          # before doing anything, so every agent_execution step sat in
          # "executing" forever while the job retried into a 500. Its three
          # dispatch branches named step types the model does not allow
          # (execute_agent, api_call, decompose) and called methods that do not
          # exist; every allowed type fell through to "Completed step type: X".
          # Fixing only the crash would have marked agent steps completed with
          # no agent ever run.
          #
          # So a step sent here FAILS, with a named reason, and never completes
          # without doing its work. Real agent_execution dispatch, with its
          # completion flowing back to the step, is filed as an offer.
          def execute_step
            step = ::Ai::GoalPlanStep.find(params[:step_id])
            plan = step.plan

            unless step.dependencies_met?
              return render_error("Step dependencies not met", status: :unprocessable_content)
            end

            reason = "no dispatcher for step type #{step.step_type}"
            step.start!
            step.fail!(reason: reason)
            Rails.logger.warn "[GoalPlan] Step #{step.id} failed: #{reason}"

            # A hash literal. Braceless, `status:` binds render_success's
            # HTTP-status keyword (api_response.rb:16) and raises; the worker
            # logs data.status, so it stays a body key. A 200 with status
            # failed is what the job logs and does not retry.
            render_success({
              step_id: step.id,
              status: "failed",
              reason: reason,
              plan_progress: plan.progress_percentage
            })
          rescue ActiveRecord::RecordNotFound => e
            render_error(e.message, status: :not_found)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class GoalPlansController < InternalBaseController
          include ::Api::V1::Internal::WorkerTenancy

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
            step = step_scope.find(params[:step_id])
            plan = step.plan

            # ACT ONLY ON AN EXECUTING STEP (review S-1). `fail!` is a bare
            # `update!`, so without this a completed step had its history
            # rewritten to failed, a step parked in awaiting_approval lost its
            # park, and pending or skipped steps failed too. In normal flow only
            # an executing step arrives here, because the enqueuer starts it
            # first. A stale or re-delivered job must change nothing, and it gets
            # a 200 so the worker does not retry it. The state goes under
            # `step_status`, never `status`, because the worker logs data.status
            # as the outcome.
            unless step.status == "executing"
              return render_success({
                step_id: step.id,
                applied: false,
                step_status: step.status,
                reason: "step is #{step.status}, not executing; nothing changed"
              })
            end

            unless step.dependencies_met?
              return render_error("Step dependencies not met", status: :unprocessable_content)
            end

            reason = "no dispatcher for step type #{step.step_type}"
            # Deterministic by its kind: every replan's step of this type fails
            # the same way, so self-correct never pays to replan it. No `start!`
            # first: the step is already executing, and re-starting it would
            # overwrite the time it really started.
            step.fail!(reason: reason, kind: "no_dispatcher")
            Rails.logger.warn "[GoalPlan] Step #{step.id} failed: #{reason}"

            # A hash literal. Braceless, `status:` binds render_success's
            # HTTP-status keyword (api_response.rb:16) and raises; the worker
            # logs data.status, so it stays a body key. A 200 with status
            # failed is what the job logs and does not retry.
            render_success({
              step_id: step.id,
              applied: true,
              status: "failed",
              reason: reason,
              plan_progress: plan.progress_percentage
            })
          rescue ActiveRecord::RecordNotFound
            # A fixed message, never the exception's: it quotes the id the caller
            # sent and the tenancy WHERE clause, so a foreign step's 404 would
            # echo that step's id back (the namespace sweep's id oracle).
            render_not_found("Goal plan step")
          end

          private

          # THE TENANCY ANCHOR (review B-1). A step has no account of its own;
          # its plan does. The lookup used to be a bare `find` on a
          # caller-supplied id, so a worker on account A could fail account B's
          # step and get a 200. Scoped through the plan's account, a foreign step
          # and a missing one both 404 (`WorkerTenancy`: never 403, which would
          # confirm the row exists elsewhere).
          def step_scope
            ::Ai::GoalPlanStep.where(plan_id: ::Ai::GoalPlan.where(account_id: worker_account_id).select(:id))
          end
        end
      end
    end
  end
end

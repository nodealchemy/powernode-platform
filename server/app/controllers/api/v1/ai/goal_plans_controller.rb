# frozen_string_literal: true

module Api
  module V1
    module Ai
      class GoalPlansController < ApplicationController
        before_action :validate_permissions
        before_action :set_goal

        # GET /api/v1/ai/goals/:goal_id/plans
        def index
          plans = @goal.plans.includes(:agent, :steps).by_version

          render_success(
            plans: plans.map { |p| serialize_plan(p) }
          )
        end

        # GET /api/v1/ai/goals/:goal_id/plans/:id
        def show
          plan = @goal.plans.includes(:agent, :steps, :approved_by).find(params[:id])

          render_success(
            plan: serialize_plan(plan, include_steps: true)
          )
        end

        private

        def set_goal
          @goal = current_account.ai_agent_goals.find(params[:goal_id])
        end

        def validate_permissions
          require_permission("ai.goals.manage")
        end

        def serialize_plan(plan, include_steps: false)
          data = {
            id: plan.id,
            status: plan.status,
            version: plan.version,
            plan_data: plan.plan_data,
            validation_result: plan.validation_result,
            risk_assessment: plan.risk_assessment,
            progress_percentage: plan.progress_percentage,
            agent: plan.agent ? { id: plan.agent.id, name: plan.agent.name } : nil,
            approved_by_id: plan.approved_by_id,
            approved_at: plan.approved_at&.iso8601,
            completed_at: plan.completed_at&.iso8601,
            created_at: plan.created_at.iso8601
          }

          if include_steps
            data[:steps] = plan.steps.in_order.map { |s| serialize_step(s) }
          end

          data
        end

        def serialize_step(step)
          {
            id: step.id,
            step_number: step.step_number,
            step_type: step.step_type,
            description: step.description,
            status: step.status,
            dependencies: step.dependencies,
            execution_config: step.execution_config,
            result_summary: step.result_summary,
            started_at: step.started_at&.iso8601,
            completed_at: step.completed_at&.iso8601
          }
        end
      end
    end
  end
end

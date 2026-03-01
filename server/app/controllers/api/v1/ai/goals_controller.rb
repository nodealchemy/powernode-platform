# frozen_string_literal: true

module Api
  module V1
    module Ai
      class GoalsController < ApplicationController
        before_action :validate_permissions
        before_action :set_goal, only: %i[show update destroy]

        # GET /api/v1/ai/goals
        def index
          goals = current_user.account.ai_agent_goals
            .includes(:agent, :parent_goal)

          goals = goals.for_agent(params[:agent_id]) if params[:agent_id].present?
          goals = goals.active if params[:status] == "active"
          goals = goals.terminal if params[:status] == "terminal"
          goals = goals.top_level if params[:top_level] == "true"
          goals = goals.stale if params[:stale] == "true"

          goals = goals.by_priority.limit(params.fetch(:limit, 50).to_i)

          render_success(
            goals: goals.map { |g| serialize_goal(g) },
            total_count: goals.size
          )
        end

        # GET /api/v1/ai/goals/:id
        def show
          render_success(serialize_goal(@goal, include_sub_goals: true))
        end

        # POST /api/v1/ai/goals
        def create
          goal = current_user.account.ai_agent_goals.build(goal_params)
          goal.created_by = current_user

          if goal.save
            render_success(serialize_goal(goal), status: :created)
          else
            render_error(goal.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH /api/v1/ai/goals/:id
        def update
          if @goal.update(goal_params)
            render_success(serialize_goal(@goal))
          else
            render_error(@goal.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/ai/goals/:id
        def destroy
          @goal.destroy!
          render_success(message: "Goal deleted")
        end

        private

        def set_goal
          @goal = current_user.account.ai_agent_goals.find(params[:id])
        end

        def goal_params
          params.permit(
            :ai_agent_id, :parent_goal_id, :title, :description,
            :goal_type, :priority, :status, :progress, :deadline,
            success_criteria: {},
            metadata: {}
          )
        end

        def validate_permissions
          require_permission("ai.goals.manage")
        end

        def serialize_goal(goal, include_sub_goals: false)
          data = {
            id: goal.id,
            title: goal.title,
            description: goal.description,
            goal_type: goal.goal_type,
            priority: goal.priority,
            status: goal.status,
            progress: goal.progress.to_f,
            deadline: goal.deadline&.iso8601,
            depth: goal.depth,
            success_criteria: goal.success_criteria,
            metadata: goal.metadata,
            agent: goal.agent ? { id: goal.agent.id, name: goal.agent.name } : nil,
            parent_goal_id: goal.parent_goal_id,
            created_by_type: goal.created_by_type,
            created_by_id: goal.created_by_id,
            created_at: goal.created_at.iso8601,
            updated_at: goal.updated_at.iso8601
          }

          if include_sub_goals
            data[:sub_goals] = goal.sub_goals.by_priority.map { |sg| serialize_goal(sg) }
          end

          data
        end
      end
    end
  end
end

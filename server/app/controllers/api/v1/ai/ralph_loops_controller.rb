# frozen_string_literal: true

module Api
  module V1
    module Ai
      class RalphLoopsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_ralph_loop, only: %i[show update destroy start pause resume cancel reset tasks task update_task iterations iteration learnings progress]
        before_action :validate_permissions

        # GET /api/v1/ai/ralph_loops
        def index
          scope = current_user.account.ai_ralph_loops.order(created_at: :desc)
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(default_agent_id: params[:default_agent_id]) if params[:default_agent_id].present?
          scope = apply_pagination(scope)

          render_success(items: scope.map(&:loop_summary), pagination: pagination_data(scope))
          log_audit_event("ai.ralph_loops.list", current_user.account)
        end

        # GET /api/v1/ai/ralph_loops/:id
        def show
          render_success(ralph_loop: @ralph_loop.loop_details)
          log_audit_event("ai.ralph_loops.read", @ralph_loop)
        end

        # POST /api/v1/ai/ralph_loops
        def create
          @ralph_loop = current_user.account.ai_ralph_loops.new(ralph_loop_params)

          saved = false
          ActiveRecord::Base.transaction do
            if @ralph_loop.save
              if params[:ralph_loop][:prd].present?
                service = build_execution_service
                parse_result = service.parse_prd(params[:ralph_loop][:prd])
                unless parse_result[:success]
                  render_error(parse_result[:error], status: :unprocessable_content)
                  raise ActiveRecord::Rollback
                end
              end
              saved = true
            else
              render_validation_error(@ralph_loop.errors)
            end
          end

          if saved
            render_success({ ralph_loop: @ralph_loop.reload.loop_details }, status: :created)
            log_audit_event("ai.ralph_loops.create", @ralph_loop)
          end
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # PATCH /api/v1/ai/ralph_loops/:id
        def update
          if @ralph_loop.update(ralph_loop_params)
            render_success(ralph_loop: @ralph_loop.loop_details)
            log_audit_event("ai.ralph_loops.update", @ralph_loop)
          else
            render_validation_error(@ralph_loop.errors)
          end
        end

        # DELETE /api/v1/ai/ralph_loops/:id
        def destroy
          if @ralph_loop.terminal? || @ralph_loop.status == "pending"
            @ralph_loop.destroy
            render_success(message: "Ralph loop deleted successfully")
            log_audit_event("ai.ralph_loops.delete", @ralph_loop)
          else
            render_error("Cannot delete a running loop. Cancel it first.", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/start
        def start
          result = build_execution_service.start_loop
          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.start", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/pause
        def pause
          result = build_execution_service.pause_loop
          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.pause", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/resume
        def resume
          result = build_execution_service.resume_loop
          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.resume", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/cancel
        def cancel
          result = build_execution_service.cancel_loop(reason: params[:reason])
          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.cancel", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/reset
        def reset
          @ralph_loop.reset!
          render_success(ralph_loop: @ralph_loop.loop_summary, message: "Loop reset successfully")
          log_audit_event("ai.ralph_loops.reset", @ralph_loop)
        rescue ::Ai::RalphLoop::InvalidTransitionError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/ralph_loops/:id/tasks
        def tasks
          scope = @ralph_loop.ralph_tasks.ordered
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = apply_pagination(scope)

          render_success(items: scope.map(&:task_summary), pagination: pagination_data(scope))
        end

        # GET /api/v1/ai/ralph_loops/:id/tasks/:task_id
        def task
          ralph_task = @ralph_loop.ralph_tasks.find_by(task_key: params[:task_id])
          ralph_task ||= @ralph_loop.ralph_tasks.find_by(id: params[:task_id])

          if ralph_task
            render_success(task: ralph_task.task_details)
          else
            render_error("Task not found", status: :not_found)
          end
        end

        # PATCH /api/v1/ai/ralph_loops/:id/tasks/:task_id
        def update_task
          ralph_task = @ralph_loop.ralph_tasks.find_by(task_key: params[:task_id])
          ralph_task ||= @ralph_loop.ralph_tasks.find_by(id: params[:task_id])

          return render_error("Task not found", status: :not_found) unless ralph_task
          return render_error("Cannot modify tasks while loop is running", status: :unprocessable_content) if @ralph_loop.running?

          if ralph_task.update(task_params)
            render_success(task: ralph_task.reload.task_details)
            log_audit_event("ai.ralph_loops.update_task", ralph_task)
          else
            render_validation_error(ralph_task.errors)
          end
        end

        # GET /api/v1/ai/ralph_loops/:id/iterations
        def iterations
          scope = @ralph_loop.ralph_iterations.recent
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(ralph_task_id: params[:task_id]) if params[:task_id].present?
          scope = apply_pagination(scope)

          render_success(items: scope.map(&:iteration_summary), pagination: pagination_data(scope))
        end

        # GET /api/v1/ai/ralph_loops/:id/iterations/:iteration_id
        def iteration
          ralph_iteration = @ralph_loop.ralph_iterations.find_by(iteration_number: params[:iteration_id])
          ralph_iteration ||= @ralph_loop.ralph_iterations.find_by(id: params[:iteration_id])

          if ralph_iteration
            render_success(iteration: ralph_iteration.iteration_details)
          else
            render_error("Iteration not found", status: :not_found)
          end
        end

        # GET /api/v1/ai/ralph_loops/:id/learnings
        def learnings
          render_success(build_execution_service.learnings)
        end

        # GET /api/v1/ai/ralph_loops/:id/progress
        def progress
          recent_commits = @ralph_loop.ralph_iterations
            .includes(:ralph_task)
            .where.not(git_commit_sha: nil)
            .order(created_at: :desc)
            .limit(10)
            .map do |i|
              {
                sha: i.git_commit_sha,
                message: "Task #{i.ralph_task&.task_key || 'unknown'} - Iteration #{i.iteration_number}",
                timestamp: i.completed_at&.iso8601
              }
            end

          render_success({
            loop_status: build_execution_service.status,
            progress_text: @ralph_loop.progress_text,
            progress_percentage: @ralph_loop.progress_percentage,
            learnings: @ralph_loop.learnings || [],
            recent_commits: recent_commits
          })
        end

        # GET /api/v1/ai/ralph_loops/statistics
        def statistics
          loops = current_user.account.ai_ralph_loops
          stats = {
            total_loops: loops.count,
            by_status: loops.group(:status).count,
            by_agent: loops.joins(:default_agent).group("ai_agents.name").count,
            total_iterations: ::Ai::RalphIteration.joins(:ralph_loop)
                                                   .where(ai_ralph_loops: { account_id: current_user.account_id }).count,
            total_tasks: ::Ai::RalphTask.joins(:ralph_loop)
                                         .where(ai_ralph_loops: { account_id: current_user.account_id }).count,
            completed_tasks: ::Ai::RalphTask.joins(:ralph_loop)
                                             .where(ai_ralph_loops: { account_id: current_user.account_id })
                                             .where(status: "passed").count,
            average_iterations_to_complete: loops.completed.average(:current_iteration)&.to_f&.round(1)
          }
          render_success(statistics: stats)
        end

        private

        def set_ralph_loop
          @ralph_loop = current_user.account.ai_ralph_loops.find_by(id: params[:id])
          render_error("Ralph loop not found", status: :not_found) unless @ralph_loop
        end

        def build_execution_service
          ::Ai::Ralph::ExecutionService.new(
            ralph_loop: @ralph_loop, account: current_user.account, user: current_user
          )
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show tasks task iterations iteration learnings progress statistics] => "ai.workflows.read",
            %w[create] => "ai.workflows.create",
            %w[update update_task] => "ai.workflows.update",
            %w[destroy] => "ai.workflows.delete",
            %w[start pause resume cancel reset] => "ai.workflows.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def ralph_loop_params
          params.require(:ralph_loop).permit(
            :name, :description, :repository_url, :branch,
            :default_agent_id, :max_iterations, :progress_text,
            :scheduling_mode,
            configuration: {}, prd_json: {}, schedule_config: {}
          )
        end

        def task_params
          params.require(:task).permit(
            :execution_type, :executor_id,
            :capability_match_strategy,
            required_capabilities: [],
            delegation_config: %i[
              timeout_seconds max_delegation_depth allow_sub_delegation
              retry_strategy fallback_executor_type fallback_executor_id
            ],
            allowed_agents: []
          )
        end
      end
    end
  end
end

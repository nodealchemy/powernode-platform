# frozen_string_literal: true

module Api
  module V1
    module Ai
      class RalphLoopsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_ralph_loop, only: %i[
          show update destroy
          start pause resume cancel reset
          run_iteration
          tasks task update_task
          iterations iteration
          learnings progress
          pause_schedule resume_schedule regenerate_webhook_token
        ]
        before_action :validate_permissions

        # =============================================================================
        # RALPH LOOPS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/ralph_loops
        def index
          scope = current_user.account.ai_ralph_loops.order(created_at: :desc)

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(ai_tool: params[:ai_tool]) if params[:ai_tool].present?

          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:loop_summary),
            pagination: pagination_data(scope)
          )
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

          ActiveRecord::Base.transaction do
            if @ralph_loop.save
              # Parse PRD if provided
              if params[:ralph_loop][:prd].present?
                service = build_execution_service
                parse_result = service.parse_prd(params[:ralph_loop][:prd])

                unless parse_result[:success]
                  render_error(parse_result[:error], status: :unprocessable_content)
                  raise ActiveRecord::Rollback
                end
              end

              render_success({ ralph_loop: @ralph_loop.reload.loop_details }, status: :created)
              log_audit_event("ai.ralph_loops.create", @ralph_loop)
            else
              render_validation_error(@ralph_loop.errors)
            end
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

        # =============================================================================
        # EXECUTION CONTROL ACTIONS
        # =============================================================================

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
          render_success(
            ralph_loop: @ralph_loop.loop_summary,
            message: "Loop reset successfully"
          )
          log_audit_event("ai.ralph_loops.reset", @ralph_loop)
        rescue ::Ai::RalphLoop::InvalidTransitionError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/run_iteration
        def run_iteration
          result = build_execution_service.run_iteration

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.run_iteration", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # =============================================================================
        # TASK MANAGEMENT
        # =============================================================================

        # GET /api/v1/ai/ralph_loops/:id/tasks
        def tasks
          scope = @ralph_loop.ralph_tasks.ordered

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:task_summary),
            pagination: pagination_data(scope)
          )
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
        # Update task executor configuration and other settings
        def update_task
          ralph_task = @ralph_loop.ralph_tasks.find_by(task_key: params[:task_id])
          ralph_task ||= @ralph_loop.ralph_tasks.find_by(id: params[:task_id])

          unless ralph_task
            return render_error("Task not found", status: :not_found)
          end

          if @ralph_loop.running?
            return render_error("Cannot modify tasks while loop is running", status: :unprocessable_content)
          end

          if ralph_task.update(task_params)
            render_success(task: ralph_task.reload.task_details)
            log_audit_event("ai.ralph_loops.update_task", ralph_task)
          else
            render_validation_error(ralph_task.errors)
          end
        end

        # =============================================================================
        # ITERATION MANAGEMENT
        # =============================================================================

        # GET /api/v1/ai/ralph_loops/:id/iterations
        def iterations
          scope = @ralph_loop.ralph_iterations.recent

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(ralph_task_id: params[:task_id]) if params[:task_id].present?
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:iteration_summary),
            pagination: pagination_data(scope)
          )
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

        # =============================================================================
        # PROGRESS AND LEARNINGS
        # =============================================================================

        # GET /api/v1/ai/ralph_loops/:id/learnings
        def learnings
          service = build_execution_service
          render_success(service.learnings)
        end

        # GET /api/v1/ai/ralph_loops/:id/progress
        def progress
          service = build_execution_service

          # Get recent commits from iterations
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
            loop_status: service.status,
            progress_text: @ralph_loop.progress_text,
            progress_percentage: @ralph_loop.progress_percentage,
            learnings: @ralph_loop.learnings || [],
            recent_commits: recent_commits
          })
        end

        # POST /api/v1/ai/ralph_loops/:id/parse_prd
        def parse_prd
          @ralph_loop = find_ralph_loop
          return unless @ralph_loop

          return render_error("PRD data is required", status: :bad_request) if params[:prd].blank?

          # Convert ActionController::Parameters to a hash for the service
          prd_data = params[:prd].respond_to?(:to_unsafe_h) ? params[:prd].to_unsafe_h : params[:prd]
          result = build_execution_service.parse_prd(prd_data)

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.parse_prd", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # =============================================================================
        # SCHEDULING ACTIONS
        # =============================================================================

        # POST /api/v1/ai/ralph_loops/:id/pause_schedule
        # Pause the automatic scheduling of a Ralph Loop
        def pause_schedule
          unless @ralph_loop.schedulable?
            return render_error("Loop is not schedulable (mode: #{@ralph_loop.scheduling_mode})")
          end

          if @ralph_loop.schedule_paused?
            return render_error("Schedule is already paused")
          end

          reason = params[:reason]
          @ralph_loop.pause_schedule!(reason: reason)

          render_success(
            ralph_loop: @ralph_loop.reload.loop_details,
            message: "Schedule paused successfully"
          )
          log_audit_event("ai.ralph_loops.pause_schedule", @ralph_loop)
        rescue StandardError => e
          render_error("Failed to pause schedule: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/resume_schedule
        # Resume the automatic scheduling of a paused Ralph Loop
        def resume_schedule
          unless @ralph_loop.schedulable?
            return render_error("Loop is not schedulable (mode: #{@ralph_loop.scheduling_mode})")
          end

          unless @ralph_loop.schedule_paused?
            return render_error("Schedule is not paused")
          end

          @ralph_loop.resume_schedule!

          render_success(
            ralph_loop: @ralph_loop.reload.loop_details,
            message: "Schedule resumed successfully",
            next_scheduled_at: @ralph_loop.next_scheduled_at&.iso8601
          )
          log_audit_event("ai.ralph_loops.resume_schedule", @ralph_loop)
        rescue StandardError => e
          render_error("Failed to resume schedule: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/regenerate_webhook_token
        # Generate a new webhook token for event-triggered loops
        def regenerate_webhook_token
          unless @ralph_loop.scheduling_mode == "event_triggered"
            return render_error("Loop is not event-triggered")
          end

          new_token = @ralph_loop.regenerate_webhook_token!

          render_success(
            webhook_token: new_token,
            webhook_url: webhook_url_for(@ralph_loop),
            message: "Webhook token regenerated successfully"
          )
          log_audit_event("ai.ralph_loops.regenerate_webhook_token", @ralph_loop)
        rescue StandardError => e
          render_error("Failed to regenerate token: #{e.message}", status: :unprocessable_content)
        end

        # =============================================================================
        # STATISTICS
        # =============================================================================

        # GET /api/v1/ai/ralph_loops/statistics
        def statistics
          loops = current_user.account.ai_ralph_loops

          stats = {
            total_loops: loops.count,
            by_status: loops.group(:status).count,
            by_ai_tool: loops.group(:ai_tool).count,
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

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_ralph_loop
          @ralph_loop = find_ralph_loop
        end

        def find_ralph_loop
          loop_record = current_user.account.ai_ralph_loops.find_by(id: params[:id])

          unless loop_record
            render_error("Ralph loop not found", status: :not_found)
            return nil
          end

          loop_record
        end

        def build_execution_service
          ::Ai::Ralph::ExecutionService.new(
            ralph_loop: @ralph_loop,
            account: current_user.account,
            user: current_user
          )
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show tasks task iterations iteration learnings progress statistics] => "ai.workflows.read",
            %w[create parse_prd] => "ai.workflows.create",
            %w[update update_task] => "ai.workflows.update",
            %w[destroy] => "ai.workflows.delete",
            %w[start pause resume cancel reset run_iteration pause_schedule resume_schedule regenerate_webhook_token] => "ai.workflows.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def webhook_url_for(ralph_loop)
          return nil unless ralph_loop.webhook_token.present?

          "#{request.base_url}/api/v1/ai/ralph_loops/webhook/#{ralph_loop.webhook_token}"
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def ralph_loop_params
          params.require(:ralph_loop).permit(
            :name, :description, :repository_url, :branch,
            :ai_tool, :max_iterations, :progress_text,
            :scheduling_mode,
            configuration: {},
            prd_json: {},
            schedule_config: {}
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

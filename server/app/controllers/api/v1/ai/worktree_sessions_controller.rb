# frozen_string_literal: true

module Api
  module V1
    module Ai
      class WorktreeSessionsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_session, only: %i[show cancel status merge_operations retry_merge conflicts file_locks acquire_locks release_locks]
        before_action :validate_permissions

        # GET /api/v1/ai/worktree_sessions
        def index
          scope = current_user.account.ai_worktree_sessions.recent

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(source_type: params[:source_type]) if params[:source_type].present?
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:session_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/ai/worktree_sessions/:id
        def show
          render_success(
            session: @session.session_summary,
            worktrees: @session.worktrees.map(&:worktree_summary),
            merge_operations: @session.merge_operations.by_order.map(&:operation_summary)
          )
        end

        # POST /api/v1/ai/worktree_sessions
        def create
          service = ::Ai::ParallelExecutionService.new(
            account: current_user.account,
            user: current_user
          )

          tasks = build_tasks_from_params
          return render_error("Tasks are required", status: :bad_request) if tasks.blank?

          result = service.start_session(
            source: resolve_source,
            tasks: tasks,
            repository_path: params[:repository_path],
            options: session_options
          )

          if result[:success]
            render_success(result, status: :created)
            log_audit_event("ai.worktree_sessions.create", current_user.account)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/worktree_sessions/:id/cancel
        def cancel
          service = ::Ai::ParallelExecutionService.new(
            account: current_user.account,
            user: current_user
          )

          result = service.cancel_session(session_id: @session.id, reason: params[:reason])

          if result[:success]
            render_success(result)
            log_audit_event("ai.worktree_sessions.cancel", @session)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/worktree_sessions/:id/status
        def status
          service = ::Ai::ParallelExecutionService.new(
            account: current_user.account,
            user: current_user
          )

          result = service.session_status(session_id: @session.id)
          render_success(result)
        end

        # GET /api/v1/ai/worktree_sessions/:id/merge_operations
        def merge_operations
          ops = @session.merge_operations.by_order
          render_success(items: ops.map(&:operation_summary))
        end

        # POST /api/v1/ai/worktree_sessions/:id/retry_merge
        def retry_merge
          return render_error("Session is not in failed state", status: :unprocessable_content) unless @session.status == "failed"

          @session.update!(status: "merging", error_message: nil, error_code: nil, error_details: {})

          # Clear failed merge operations
          @session.merge_operations.where(status: %w[failed conflict]).destroy_all

          WorkerJobService.enqueue_ai_merge_execution(@session.id)

          render_success(session: @session.reload.session_summary, message: "Merge retry started")
          log_audit_event("ai.worktree_sessions.retry_merge", @session)
        end

        # GET /api/v1/ai/worktree_sessions/:id/conflicts
        def conflicts
          service = ::Ai::Git::ConflictDetectionService.new(session: @session)
          result = service.detect
          render_success(result)
        end

        # GET /api/v1/ai/worktree_sessions/:id/file_locks
        def file_locks
          service = ::Ai::FileLockService.new(session: @session)
          render_success(items: service.active_locks)
        end

        # POST /api/v1/ai/worktree_sessions/:id/acquire_locks
        def acquire_locks
          worktree = @session.worktrees.find(params[:worktree_id])
          service = ::Ai::FileLockService.new(session: @session)

          result = service.acquire(
            worktree: worktree,
            file_paths: params[:file_paths],
            lock_type: params[:lock_type] || "exclusive",
            ttl_seconds: params[:ttl_seconds]&.to_i
          )

          if result[:success]
            render_success(result)
          else
            render_error("Lock conflicts detected", status: :conflict)
          end
        end

        # POST /api/v1/ai/worktree_sessions/:id/release_locks
        def release_locks
          worktree = @session.worktrees.find(params[:worktree_id])
          service = ::Ai::FileLockService.new(session: @session)

          result = if params[:file_paths].present?
            service.release_files(worktree: worktree, file_paths: params[:file_paths])
          else
            service.release(worktree: worktree)
          end

          render_success(result)
        end

        private

        def set_session
          @session = current_user.account.ai_worktree_sessions.find_by(id: params[:id])
          render_error("Worktree session not found", status: :not_found) unless @session
        end

        def validate_permissions
          return if current_worker

          permission_map = {
            %w[index show status merge_operations conflicts file_locks] => "ai.workflows.read",
            %w[create] => "ai.workflows.create",
            %w[cancel retry_merge acquire_locks release_locks] => "ai.workflows.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def build_tasks_from_params
          return [] unless params[:tasks].is_a?(Array)

          params[:tasks].map do |task_params|
            {
              branch_suffix: task_params[:branch_suffix],
              agent_id: task_params[:agent_id],
              container_template_id: task_params[:container_template_id],
              metadata: task_params[:metadata]&.to_unsafe_h || {}
            }
          end
        end

        def resolve_source
          return nil unless params[:source_type].present? && params[:source_id].present?

          case params[:source_type]
          when "Ai::RalphLoop"
            current_user.account.ai_ralph_loops.find_by(id: params[:source_id])
          when "Ai::AgentTeam"
            current_user.account.ai_agent_teams.find_by(id: params[:source_id])
          end
        end

        def session_options
          {
            base_branch: params[:base_branch],
            merge_strategy: params[:merge_strategy],
            merge_config: params[:merge_config]&.to_unsafe_h,
            max_parallel: params[:max_parallel]&.to_i,
            auto_cleanup: params.fetch(:auto_cleanup, true),
            execution_mode: params[:execution_mode],
            max_duration_seconds: params[:max_duration_seconds]&.to_i,
            configuration: params[:configuration]&.to_unsafe_h || {},
            metadata: params[:metadata]&.to_unsafe_h || {}
          }.compact
        end
      end
    end
  end
end

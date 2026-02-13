# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamExecutionController < ApplicationController
        rescue_from ::Ai::TeamAuthorityService::AuthorityViolation do |e|
          render_error(e.message, status: :forbidden)
        end

        before_action :authenticate_request
        before_action :set_team_service
        before_action :set_team, only: %i[list_executions]
        before_action :set_execution, only: %i[
          show_execution pause_execution resume_execution cancel_execution complete_execution
          create_task list_tasks show_task assign_task start_task complete_task fail_task delegate_task
          send_message list_messages reply_to_message
          execution_details
          list_task_reviews
        ]

        # ============================================================================
        # EXECUTIONS
        # ============================================================================

        # GET /api/v1/ai/teams/:team_id/executions
        def list_executions
          executions = @execution_service.list_executions(@team.id, filter_params)

          render_success(
            executions: executions.map { |e| serialize_execution(e) },
            total_count: executions.respond_to?(:total_count) ? executions.total_count : executions.count
          )
        end

        # POST /api/v1/ai/teams/:team_id/executions
        def start_execution
          team = @crud_service.get_team(params[:team_id])
          execution = @execution_service.start_execution(team.id, execution_params, user: current_user)
          render_success(serialize_execution(execution, detailed: true), status: :created)
        end

        # GET /api/v1/ai/teams/executions/:id
        def show_execution
          render_success(serialize_execution(@execution, detailed: true))
        end

        # POST /api/v1/ai/teams/executions/:id/pause
        def pause_execution
          execution = @execution_service.pause_execution(@execution.id)
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/resume
        def resume_execution
          execution = @execution_service.resume_execution(@execution.id)
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/cancel
        def cancel_execution
          execution = @execution_service.cancel_execution(@execution.id, reason: params[:reason])
          render_success(serialize_execution(execution))
        end

        # POST /api/v1/ai/teams/executions/:id/complete
        def complete_execution
          execution = @execution_service.complete_execution(@execution.id, params[:result] || {})
          render_success(serialize_execution(execution))
        end

        # GET /api/v1/ai/teams/executions/:id/details
        def execution_details
          details = @analytics_service.get_execution_details(@execution.id)
          render_success(details)
        end

        # ============================================================================
        # TASKS
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/tasks
        def list_tasks
          tasks = @execution.tasks.includes(:assigned_role, :assigned_agent)
          render_success(tasks: tasks.map { |t| serialize_task(t) })
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks
        def create_task
          task = @execution_service.create_task(@execution.id, task_params)
          render_success(serialize_task(task), status: :created)
        end

        # GET /api/v1/ai/teams/executions/:execution_id/tasks/:id
        def show_task
          task = @execution_service.get_task(@execution.id, params[:id])
          render_success(serialize_task(task, detailed: true))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/assign
        def assign_task
          task = @execution_service.assign_task(@execution.id, params[:id], role_id: params[:role_id], agent_id: params[:agent_id])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/start
        def start_task
          task = @execution_service.start_task(@execution.id, params[:id])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/complete
        def complete_task
          task = @execution_service.complete_task(@execution.id, params[:id], output: params[:output] || {})
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/fail
        def fail_task
          task = @execution_service.fail_task(@execution.id, params[:id], reason: params[:reason])
          render_success(serialize_task(task))
        end

        # POST /api/v1/ai/teams/executions/:execution_id/tasks/:id/delegate
        def delegate_task
          new_task = @execution_service.delegate_task(@execution.id, params[:id], to_role_id: params[:to_role_id], to_agent_id: params[:to_agent_id])
          render_success(serialize_task(new_task))
        end

        # ============================================================================
        # TASK REVIEWS
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/tasks/:task_id/reviews
        def list_task_reviews
          task = @execution_service.get_task(@execution.id, params[:task_id])
          reviews = @crud_service.list_task_reviews(task.id)
          render_success(reviews: reviews.map { |r| serialize_review(r) })
        end

        # ============================================================================
        # MESSAGES
        # ============================================================================

        # GET /api/v1/ai/teams/executions/:execution_id/messages
        def list_messages
          messages = @execution_service.get_messages(@execution.id, message_filter_params)
          render_success(messages: messages.map { |m| serialize_message(m) })
        end

        # POST /api/v1/ai/teams/executions/:execution_id/messages
        def send_message
          message = @execution_service.send_message(@execution.id, message_params)
          render_success(serialize_message(message), status: :created)
        end

        # POST /api/v1/ai/teams/executions/:execution_id/messages/:id/reply
        def reply_to_message
          reply = @execution_service.reply_to_message(@execution.id, params[:id], reply_params)
          render_success(serialize_message(reply))
        end

        private

        def set_team_service
          @crud_service = ::Ai::Teams::CrudService.new(account: current_account)
          @execution_service = ::Ai::Teams::ExecutionService.new(account: current_account)
          @analytics_service = ::Ai::Teams::AnalyticsService.new(account: current_account)
        end

        def set_team
          @team = @crud_service.get_team(params[:team_id] || params[:id])
        end

        def set_execution
          @execution = @execution_service.get_execution(params[:execution_id] || params[:id])
        end

        def filter_params
          params.permit(:status, :topology, :page, :per_page)
        end

        def execution_params
          params.permit(
            :objective, :workflow_run_id, input_context: {},
            tasks: [ :description, :expected_output, :task_type, :role_id, { input_data: {} } ]
          )
        end

        def task_params
          params.permit(
            :description, :expected_output, :task_type, :priority,
            :max_retries, :parent_task_id, :role_id, input_data: {}
          )
        end

        def message_params
          params.permit(
            :channel_id, :from_role_id, :to_role_id, :task_id,
            :message_type, :content, :priority, :requires_response,
            structured_content: {}, attachments: []
          )
        end

        def message_filter_params
          params.permit(:channel_id, :from_role_id, :message_type, :page, :per_page)
        end

        def reply_params
          params.permit(:from_role_id, :content, :message_type)
        end

        def serialize_execution(execution, detailed: false)
          data = {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            objective: execution.objective,
            tasks_total: execution.tasks_total,
            tasks_completed: execution.tasks_completed,
            tasks_failed: execution.tasks_failed,
            progress_percentage: execution.progress_percentage,
            messages_exchanged: execution.messages_exchanged,
            total_tokens_used: execution.total_tokens_used,
            total_cost_usd: execution.total_cost_usd,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            duration_ms: execution.duration_ms,
            created_at: execution.created_at
          }

          if detailed
            data[:input_context] = execution.input_context
            data[:output_result] = execution.output_result
            data[:shared_memory] = execution.shared_memory
            data[:termination_reason] = execution.termination_reason
            data[:performance_metrics] = execution.performance_metrics
          end

          data
        end

        def serialize_task(task, detailed: false)
          data = {
            id: task.id,
            task_id: task.task_id,
            description: task.description,
            status: task.status,
            task_type: task.task_type,
            priority: task.priority,
            assigned_role_id: task.assigned_role_id,
            assigned_role_name: task.assigned_role&.role_name,
            assigned_agent_id: task.assigned_agent_id,
            tokens_used: task.tokens_used,
            cost_usd: task.cost_usd,
            retry_count: task.retry_count,
            started_at: task.started_at,
            completed_at: task.completed_at,
            duration_ms: task.duration_ms
          }

          if detailed
            data[:expected_output] = task.expected_output
            data[:input_data] = task.input_data
            data[:output_data] = task.output_data
            data[:tools_used] = task.tools_used
            data[:failure_reason] = task.failure_reason
            data[:parent_task_id] = task.parent_task_id
          end

          data
        end

        def serialize_message(message)
          {
            id: message.id,
            sequence_number: message.sequence_number,
            message_type: message.message_type,
            content: message.content,
            from_role_id: message.from_role_id,
            from_role_name: message.from_role&.role_name,
            to_role_id: message.to_role_id,
            to_role_name: message.to_role&.role_name,
            channel_id: message.channel_id,
            priority: message.priority,
            requires_response: message.requires_response,
            responded_at: message.responded_at,
            created_at: message.created_at,
            structured_content: message.structured_content,
            attachments: message.attachments,
            read_at: message.read_at,
            in_reply_to_id: message.in_reply_to_id,
            reply_count: message.replies.count
          }
        end

        def serialize_review(review)
          {
            id: review.id,
            review_id: review.review_id,
            status: review.status,
            review_mode: review.review_mode,
            quality_score: review.quality_score,
            findings: review.findings,
            completeness_checks: review.completeness_checks,
            approval_notes: review.approval_notes,
            rejection_reason: review.rejection_reason,
            revision_count: review.revision_count,
            review_duration_ms: review.review_duration_ms,
            reviewer_role_id: review.reviewer_role_id,
            reviewer_agent_id: review.reviewer_agent_id,
            team_task_id: review.team_task_id,
            created_at: review.created_at
          }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AgentTeamExecutionsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :set_team
        before_action :set_execution, only: [:show, :cancel, :pause, :resume, :retry_execution]

        # GET /api/v1/ai/agent_teams/:agent_team_id/executions
        def index
          executions = @team.team_executions
                            .includes(:triggered_by)
                            .order(created_at: :desc)

          executions = executions.where(status: params[:status]) if params[:status].present?

          page = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min
          total = executions.count
          executions = executions.offset((page - 1) * per_page).limit(per_page)

          render_success(
            executions.map { |e| serialize_execution(e) },
            meta: {
              total: total,
              page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil
            }
          )
        end

        # GET /api/v1/ai/agent_teams/:agent_team_id/executions/:id
        def show
          render_success(serialize_execution_detail(@execution))
        end

        # POST /api/v1/ai/agent_teams/:agent_team_id/executions/:id/cancel
        def cancel
          unless @execution.active?
            return render_error("Execution is not active", :unprocessable_content)
          end

          @execution.update!(control_signal: "cancel")
          audit_log("ai_agent_team.execution_cancel_requested", execution_id: @execution.execution_id)
          render_success({ status: "cancel_requested", execution_id: @execution.execution_id })
        end

        # POST /api/v1/ai/agent_teams/:agent_team_id/executions/:id/pause
        def pause
          unless @execution.status == "running"
            return render_error("Execution is not running", :unprocessable_content)
          end

          @execution.update!(control_signal: "pause")
          audit_log("ai_agent_team.execution_pause_requested", execution_id: @execution.execution_id)
          render_success({ status: "pause_requested", execution_id: @execution.execution_id })
        end

        # POST /api/v1/ai/agent_teams/:agent_team_id/executions/:id/resume
        def resume
          unless @execution.control_signal == "pause"
            return render_error("Execution is not paused", :unprocessable_content)
          end

          @execution.update!(control_signal: nil)
          audit_log("ai_agent_team.execution_resume_requested", execution_id: @execution.execution_id)
          render_success({ status: "resume_requested", execution_id: @execution.execution_id })
        end

        # POST /api/v1/ai/agent_teams/:agent_team_id/executions/:id/retry
        def retry_execution
          unless @execution.finished?
            return render_error("Execution has not finished", :unprocessable_content)
          end

          new_execution_args = {
            team_id: @team.id,
            user_id: current_user.id,
            input: @execution.input_context || {},
            context: { retried_from: @execution.execution_id }
          }

          ::Ai::AgentTeamExecutionJob.perform_later(new_execution_args)
          audit_log("ai_agent_team.execution_retried",
            original_execution_id: @execution.execution_id)
          render_success({ status: "retry_queued", original_execution_id: @execution.execution_id })
        end

        private

        def set_team
          @team = current_account.ai_agent_teams.find(params[:agent_team_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Team")
        end

        def set_execution
          @execution = @team.team_executions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Execution")
        end

        def serialize_execution(execution)
          {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            objective: execution.objective,
            started_at: execution.started_at&.iso8601,
            completed_at: execution.completed_at&.iso8601,
            duration_ms: execution.duration_ms,
            tasks_total: execution.tasks_total,
            tasks_completed: execution.tasks_completed,
            tasks_failed: execution.tasks_failed,
            progress_percentage: execution.progress_percentage,
            messages_exchanged: execution.messages_exchanged,
            total_tokens_used: execution.total_tokens_used,
            total_cost_usd: execution.total_cost_usd,
            control_signal: execution.try(:control_signal),
            termination_reason: execution.termination_reason,
            triggered_by: execution.triggered_by ? {
              id: execution.triggered_by.id,
              name: execution.triggered_by.name
            } : nil,
            created_at: execution.created_at.iso8601
          }
        end

        def serialize_execution_detail(execution)
          serialize_execution(execution).merge(
            input_context: execution.input_context,
            output_result: execution.output_result,
            total_tokens_used: execution.total_tokens_used,
            total_cost_usd: execution.total_cost_usd,
            messages_exchanged: execution.messages_exchanged,
            control_signal: execution.try(:control_signal),
            paused_at: execution.try(:paused_at)&.iso8601,
            resume_count: execution.try(:resume_count) || 0,
            per_member_costs: aggregate_member_costs(execution),
            tasks: execution.tasks.order(:created_at).map { |t| serialize_task(t) },
            messages: execution.messages.order(:created_at).limit(100).map { |m| serialize_message(m) }
          )
        end

        def serialize_task(task)
          {
            id: task.id,
            title: task.try(:title),
            status: task.status,
            assigned_to: task.try(:assigned_to),
            created_at: task.created_at.iso8601,
            completed_at: task.try(:completed_at)&.iso8601
          }
        end

        def serialize_message(message)
          {
            id: message.id,
            content: message.try(:content),
            sender: message.try(:sender),
            created_at: message.created_at.iso8601
          }
        end

        def aggregate_member_costs(execution)
          # Find all agent executions linked to this team execution
          agent_executions = ::Ai::AgentExecution.where(
            "execution_context->>'team_execution_id' = ?", execution.id.to_s
          ).select(:id, :ai_agent_id, :tokens_used, :cost_usd, :duration_ms, :status)

          agent_executions.map do |ae|
            agent = ::Ai::Agent.find_by(id: ae.ai_agent_id)
            {
              agent_id: ae.ai_agent_id,
              agent_name: agent&.name || "Unknown",
              tokens_used: ae.tokens_used || 0,
              cost_usd: ae.cost_usd || 0,
              duration_ms: ae.duration_ms || 0,
              status: ae.status
            }
          end
        rescue StandardError => e
          Rails.logger.warn("[AgentTeamExecutionsController] Failed to aggregate member costs: #{e.message}")
          []
        end
      end
    end
  end
end

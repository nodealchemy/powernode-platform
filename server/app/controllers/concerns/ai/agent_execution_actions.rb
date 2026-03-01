# frozen_string_literal: true

# Actions for managing agent executions
#
# Provides CRUD and lifecycle actions for executions nested under agents:
# - List, show, update, destroy executions
# - Execution lifecycle: cancel, retry
# - Execution logs access
#
# Requires:
# - current_user method
# - @execution to be set for single-execution actions (use before_action :set_agent_execution)
# - execution_service method to be defined
# - AgentSerialization concern for serialization methods
# - ResourceFiltering concern for apply_execution_filters and apply_pagination
#
# Usage:
#   class AgentsController < ApplicationController
#     include Ai::AgentExecutionActions
#     include Ai::AgentSerialization
#     include Ai::ResourceFiltering
#
#     before_action :set_agent_execution, only: [:execution_show, :execution_update, ...]
#
#     private
#
#     def execution_service
#       @execution_service ||= ::Ai::Agents::ExecutionService.new(execution: @execution, user: current_user)
#     end
#   end
#
module Ai
  module AgentExecutionActions
    extend ActiveSupport::Concern

    # =============================================================================
    # EXECUTION CRUD
    # =============================================================================

    # GET /api/v1/ai/agents/:agent_id/executions
    def executions_index
      executions = if params[:agent_id].present?
                     agent = current_user.account.ai_agents.find(params[:agent_id])
                     agent.executions
      else
                     ::Ai::AgentExecution.joins(:agent).where(ai_agents: { account_id: current_user.account_id })
      end

      executions = executions.includes(:agent, :provider, :user)
      executions = apply_execution_filters(executions)
      executions = apply_pagination(executions.order(created_at: :desc))

      render_success(
        items: executions.map { |exec| serialize_execution(exec) },
        pagination: pagination_data(executions)
      )
    end

    # GET /api/v1/ai/agents/:agent_id/executions/:execution_id
    def execution_show
      serialized = serialize_execution_detail(@execution)
      clean_data = JSON.parse(serialized.to_json)

      render_success(execution: clean_data)
    end

    # PATCH /api/v1/ai/agents/:agent_id/executions/:execution_id
    def execution_update
      require_permission("ai.agents.update") unless current_worker

      result = execution_service.update(execution_update_params)

      if result.success?
        serialized = serialize_execution_detail(result.data[:execution])
        clean_data = JSON.parse(serialized.to_json)
        render_success(execution: clean_data, message: "Execution updated successfully")
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # DELETE /api/v1/ai/agents/:agent_id/executions/:execution_id
    def execution_destroy
      if @execution.destroy
        render_success(message: "Execution deleted successfully")
        log_audit_event("ai.agents.execution.delete", @execution)
      else
        render_error("Failed to delete execution", status: :unprocessable_content)
      end
    end

    # =============================================================================
    # EXECUTION LIFECYCLE
    # =============================================================================

    # POST /api/v1/ai/agents/:agent_id/executions/:execution_id/cancel
    def execution_cancel
      result = execution_service.cancel(reason: params[:reason] || "Cancelled by user")

      if result.success?
        render_success(
          execution: serialize_execution(result.data[:execution]),
          message: "Execution cancelled successfully"
        )
        log_audit_event("ai.agents.execution.cancel", @execution)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # POST /api/v1/ai/agents/:agent_id/executions/:execution_id/retry
    def execution_retry
      result = execution_service.retry

      if result.success?
        render_success(
          { execution: serialize_execution(result.data[:execution]), message: "Execution retried successfully" },
          status: :created
        )
        log_audit_event("ai.agents.execution.retry", result.data[:execution], original_execution_id: result.data[:original_execution_id])
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # =============================================================================
    # EXECUTION LOGS
    # =============================================================================

    # GET /api/v1/ai/agents/:agent_id/executions/:execution_id/logs
    def execution_logs
      render_success({ logs: execution_service.logs, execution_id: @execution.execution_id })
    end

    private

    # Execution parameter handling (can be overridden in including controller)
    def execution_update_params
      params.require(:execution).permit(
        :status, :started_at, :completed_at, :cost_usd, :duration_ms, :tokens_used,
        output_data: {}, error_details: {}, metadata: {}
      )
    end
  end
end

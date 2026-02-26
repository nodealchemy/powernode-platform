# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class AgentExecutionsController < InternalBaseController
          before_action :set_execution

          # GET /api/v1/internal/ai/executions/:id
          #
          # Returns execution details with nested agent data for worker consumption.
          def show
            render_success(agent_execution: serialize_for_worker(@execution))
          end

          # PATCH /api/v1/internal/ai/executions/:id
          #
          # Updates execution status and output from worker.
          def update
            permitted = execution_params
            @execution.assign_attributes(permitted)

            if @execution.save
              render_success(agent_execution: serialize_for_worker(@execution))
            else
              render_error("Failed to update execution: #{@execution.errors.full_messages.join(', ')}", status: :unprocessable_entity)
            end
          end

          # POST /api/v1/internal/ai/executions/:id/cancel
          #
          # Cancels a running or pending execution (used by timeout cleanup).
          def cancel
            reason = params[:reason] || "Cancelled by worker"

            if @execution.status.in?(%w[pending queued running])
              @execution.update!(status: "cancelled", error_message: reason, completed_at: Time.current)
              render_success(agent_execution: serialize_for_worker(@execution), message: "Execution cancelled")
            else
              render_error("Execution not in cancellable state (#{@execution.status})", status: :unprocessable_entity)
            end
          end

          private

          def set_execution
            @execution = ::Ai::AgentExecution.includes(:agent).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Execution not found", status: :not_found)
          end

          def execution_params
            params.require(:agent_execution).permit(
              :status, :error_message, :cost_usd, :duration_ms,
              :tokens_used, :completed_at, :started_at,
              output_data: {}
            )
          end

          def serialize_for_worker(execution)
            agent = execution.agent

            {
              id: execution.id,
              status: execution.status,
              input_parameters: execution.input_parameters,
              output_data: execution.output_data,
              error_message: execution.error_message,
              cost_usd: execution.cost_usd,
              duration_ms: execution.duration_ms,
              tokens_used: execution.tokens_used,
              started_at: execution.started_at,
              completed_at: execution.completed_at,
              created_at: execution.created_at,
              ai_agent: agent ? {
                id: agent.id,
                name: agent.name,
                agent_type: agent.agent_type,
                status: agent.status,
                model: agent.model,
                mcp_metadata: agent.mcp_metadata,
                mcp_tool_manifest: agent.mcp_tool_manifest
              } : nil
            }
          end
        end
      end
    end
  end
end

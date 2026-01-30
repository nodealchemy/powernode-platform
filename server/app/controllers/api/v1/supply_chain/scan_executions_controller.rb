# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ScanExecutionsController < BaseController
        before_action :require_read_permission, only: [:index, :show, :logs]
        before_action :require_write_permission, only: [:cancel]
        before_action :set_execution, only: [:show, :cancel, :logs]

        # GET /api/v1/supply_chain/scan_executions
        def index
          @executions = current_account.supply_chain_scan_executions
                                       .includes(:scan_instance, :triggered_by)
                                       .order(created_at: :desc)

          @executions = @executions.where(status: params[:status]) if params[:status].present?
          @executions = @executions.where(trigger_type: params[:trigger_type]) if params[:trigger_type].present?

          if params[:scan_instance_id].present?
            @executions = @executions.where(scan_instance_id: params[:scan_instance_id])
          end

          if params[:since].present?
            @executions = @executions.where("created_at >= ?", Time.parse(params[:since]))
          end

          @executions = paginate(@executions)

          render_success(
            { scan_executions: @executions.map { |e| serialize_execution(e) } },
            meta: pagination_meta
          )
        end

        # GET /api/v1/supply_chain/scan_executions/:id
        def show
          render_success({ scan_execution: serialize_execution(@execution, include_details: true) })
        end

        # POST /api/v1/supply_chain/scan_executions/:id/cancel
        def cancel
          unless %w[pending running].include?(@execution.status)
            return render_error("Execution cannot be cancelled in current status", status: :unprocessable_entity)
          end

          @execution.cancel!

          render_success(
            { scan_execution: serialize_execution(@execution) },
            message: "Scan execution cancelled"
          )
        end

        # GET /api/v1/supply_chain/scan_executions/:id/logs
        def logs
          # logs is a text field, parse and return as array
          log_lines = parse_logs(@execution.logs)

          render_success(
            {
              execution_id: @execution.id,
              logs: log_lines
            },
            meta: { total: log_lines.length }
          )
        end

        private

        def set_execution
          @execution = current_account.supply_chain_scan_executions.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Scan execution not found", status: :not_found)
        end

        def serialize_execution(execution, include_details: false)
          data = {
            id: execution.id,
            execution_id: execution.execution_id,
            status: execution.status,
            trigger_type: execution.trigger_type,
            scan_instance: execution.scan_instance ? {
              id: execution.scan_instance.id,
              name: execution.scan_instance.name
            } : nil,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            duration_ms: execution.duration_ms,
            triggered_by: execution.triggered_by ? {
              id: execution.triggered_by.id,
              name: execution.triggered_by.name
            } : nil,
            error_message: execution.error_message,
            created_at: execution.created_at
          }

          if include_details
            data[:input_data] = execution.input_data
            data[:output_data] = execution.output_data
            data[:logs] = execution.logs
            data[:metadata] = execution.metadata
          end

          data
        end

        def parse_logs(logs_text)
          return [] if logs_text.blank?

          logs_text.split("\n").reject(&:blank?).map.with_index do |line, idx|
            {
              id: idx + 1,
              message: line.sub(/^\[.*?\]\s*/, ""),
              level: "info",
              timestamp: line.match(/\[(.*?)\]/)&.captures&.first
            }
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Integrations
      class ExecutionsController < ApplicationController
        before_action :authenticate_request
        before_action :set_execution, only: [:show, :retry, :cancel]

        # GET /api/v1/integrations/executions
        def index
          authorize_action!("integrations.read")

          scope = Integration::Execution.where(account: current_account)

          # Filter by instance
          if params[:instance_id].present?
            scope = scope.where(integration_instance_id: params[:instance_id])
          end

          # Filter by status
          scope = scope.where(status: params[:status]) if params[:status].present?

          # Filter by date range
          scope = scope.where("created_at >= ?", Time.parse(params[:since])) if params[:since].present?
          scope = scope.where("created_at <= ?", Time.parse(params[:until])) if params[:until].present?

          executions = scope
            .includes(:integration_instance)
            .order(created_at: :desc)
            .page(pagination_params[:page])
            .per(pagination_params[:per_page])

          render_success({
            executions: executions.map(&:execution_summary),
            pagination: pagination_meta(executions)
          })
        end

        # GET /api/v1/integrations/executions/:id
        def show
          authorize_action!("integrations.read")

          render_success({ execution: @execution.execution_details })
        end

        # POST /api/v1/integrations/executions/:id/retry
        def retry
          authorize_action!("integrations.execute")

          result = ::Integrations::ExecutionService.retry_execution(
            execution: @execution,
            context: { request_id: request.request_id, retried_by: current_user.id }
          )

          if result[:success]
            render_success({ result: result })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/integrations/executions/:id/cancel
        def cancel
          authorize_action!("integrations.execute")

          result = ::Integrations::ExecutionService.cancel_execution(execution: @execution)

          if result[:success]
            render_success({ result: result })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/integrations/executions/stats
        def stats
          authorize_action!("integrations.read")

          period = (params[:period] || 30).to_i.days

          scope = Integration::Execution
            .where(account: current_account)
            .where("created_at >= ?", period.ago)

          if params[:instance_id].present?
            scope = scope.where(integration_instance_id: params[:instance_id])
          end

          stats = {
            total: scope.count,
            completed: scope.where(status: "completed").count,
            failed: scope.where(status: "failed").count,
            cancelled: scope.where(status: "cancelled").count,
            running: scope.where(status: "running").count,
            queued: scope.where(status: "queued").count,
            avg_execution_time_ms: scope.where(status: "completed").average(:execution_time_ms)&.round(2),
            success_rate: calculate_success_rate(scope),
            by_day: scope.group_date(:created_at, period: :day).count,
            by_status: scope.group(:status).count
          }

          render_success({ stats: stats })
        end

        private

        def set_execution
          @execution = Integration::Execution.find_by(id: params[:id], account: current_account)

          render_not_found("Execution") unless @execution
        end

        def calculate_success_rate(scope)
          completed = scope.where(status: %w[completed failed])
          return 0.0 if completed.count.zero?

          (scope.where(status: "completed").count.to_f / completed.count * 100).round(2)
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("You don't have permission to perform this action")
          end
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end

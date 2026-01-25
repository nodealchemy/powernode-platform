# frozen_string_literal: true

module Api
  module V1
    module Devops
      class PipelineRunsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [:index, :show, :logs]
        before_action :require_write_permission, only: [:cancel, :retry]
        before_action :set_pipeline_run, only: [:show, :cancel, :retry, :logs]

        # GET /api/v1/devops/pipeline_runs
        def index
          runs = ::Devops::PipelineRun.joins(:pipeline)
                                      .where(devops_pipelines: { account_id: current_user.account_id })
                                      .includes(:pipeline, :triggered_by)
                                      .order(created_at: :desc)

          # Filter by pipeline if provided
          runs = runs.where(ci_cd_pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?

          # Filter by status if provided
          runs = runs.where(status: params[:status]) if params[:status].present?

          # Filter by trigger type if provided
          runs = runs.where(trigger_type: params[:trigger_type]) if params[:trigger_type].present?

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = [(params[:per_page] || 20).to_i, 100].min
          total = runs.count
          runs = runs.offset((page - 1) * per_page).limit(per_page)

          render_success({
            pipeline_runs: serialize_collection(runs),
            meta: {
              total: total,
              page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              status_counts: status_counts
            }
          })

          log_audit_event("devops.pipeline_runs.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list pipeline runs: #{e.message}"
          render_error("Failed to list pipeline runs", status: :internal_server_error)
        end

        # GET /api/v1/devops/pipeline_runs/:id
        def show
          render_success({
            pipeline_run: serialize_pipeline_run(@pipeline_run, include_steps: true)
          })

          log_audit_event("devops.pipeline_runs.read", @pipeline_run)
        rescue StandardError => e
          Rails.logger.error "Failed to get pipeline run: #{e.message}"
          render_error("Failed to get pipeline run", status: :internal_server_error)
        end

        # POST /api/v1/devops/pipeline_runs/:id/cancel
        def cancel
          unless @pipeline_run.can_cancel?
            render_error("Pipeline run cannot be cancelled in current state", status: :unprocessable_content)
            return
          end

          @pipeline_run.cancel!

          render_success({
            pipeline_run: serialize_pipeline_run(@pipeline_run),
            message: "Pipeline run cancelled successfully"
          })

          log_audit_event("devops.pipeline_runs.cancel", @pipeline_run)
        rescue StandardError => e
          render_internal_error("Failed to cancel pipeline run", exception: e)
        end

        # POST /api/v1/devops/pipeline_runs/:id/retry
        def retry
          unless @pipeline_run.can_retry?
            render_error("Pipeline run cannot be retried in current state", status: :unprocessable_content)
            return
          end

          new_run = @pipeline_run.pipeline.pipeline_runs.create!(
            status: :pending,
            trigger_type: :retry,
            trigger_context: @pipeline_run.trigger_context.merge(
              retry_of: @pipeline_run.id,
              original_trigger_type: @pipeline_run.trigger_type
            ),
            triggered_by: current_user
          )

          # Trigger async execution via worker service
          begin
            WorkerJobService.enqueue_job(
              "Devops::PipelineExecutionJob",
              args: [new_run.id],
              queue: "devops_high"
            )
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn "Worker service unavailable for retry: #{e.message}"
          end

          render_success({
            pipeline_run: serialize_pipeline_run(new_run),
            original_run_id: @pipeline_run.id,
            message: "Pipeline run retry initiated"
          }, status: :created)

          log_audit_event("devops.pipeline_runs.retry", new_run)
        rescue StandardError => e
          render_internal_error("Failed to retry pipeline run", exception: e)
        end

        # GET /api/v1/devops/pipeline_runs/:id/logs
        def logs
          step_executions = @pipeline_run.step_executions.includes(:pipeline_step).order(:created_at)

          logs_data = step_executions.map do |execution|
            {
              step_id: execution.id,
              step_name: execution.step_name,
              step_type: execution.step_type,
              status: execution.status,
              started_at: execution.started_at,
              completed_at: execution.completed_at,
              duration_seconds: execution.duration_seconds,
              logs: execution.logs,
              outputs: execution.outputs,
              error_message: execution.error_message
            }
          end

          render_success({
            pipeline_run_id: @pipeline_run.id,
            status: @pipeline_run.status,
            logs: logs_data,
            retrieved_at: Time.current
          })

          log_audit_event("devops.pipeline_runs.logs", @pipeline_run)
        rescue StandardError => e
          Rails.logger.error "Failed to get pipeline run logs: #{e.message}"
          render_error("Failed to get pipeline run logs", status: :internal_server_error)
        end

        private

        def set_pipeline_run
          @pipeline_run = ::Devops::PipelineRun.joins(:pipeline)
                                               .where(devops_pipelines: { account_id: current_user.account_id })
                                               .includes(:pipeline, :triggered_by, step_executions: :pipeline_step)
                                               .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline run not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("devops.pipeline_runs.read")

          render_error("Insufficient permissions to view pipeline runs", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("devops.pipeline_runs.write")

          render_error("Insufficient permissions to manage pipeline runs", status: :forbidden)
        end

        def status_counts
          ::Devops::PipelineRun.joins(:pipeline)
                               .where(devops_pipelines: { account_id: current_user.account_id })
                               .group(:status)
                               .count
        end

        def serialize_collection(runs)
          runs.map { |r| serialize_pipeline_run(r) }
        end

        def serialize_pipeline_run(run, include_steps: false)
          result = ::Devops::PipelineRunSerializer.new(run).serializable_hash[:data][:attributes]
          result[:id] = run.id
          result[:pipeline_name] = run.pipeline.name
          result[:pipeline_slug] = run.pipeline.slug

          if include_steps
            # Include step execution records
            result[:step_executions] = run.step_executions.includes(:pipeline_step).order(:created_at).map do |execution|
              ::Devops::StepExecutionSerializer.new(execution).serializable_hash[:data][:attributes].merge(id: execution.id)
            end
          end

          # Always include pipeline step definitions for execution
          result[:steps] = run.pipeline.pipeline_steps.active.order(:position).map do |step|
            {
              id: step.id,
              name: step.name,
              step_type: step.step_type,
              position: step.position,
              is_active: step.is_active,
              continue_on_error: step.continue_on_error,
              configuration: step.configuration
            }
          end

          result
        end
      end
    end
  end
end

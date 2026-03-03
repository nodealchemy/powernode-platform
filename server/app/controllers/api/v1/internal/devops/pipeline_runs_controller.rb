# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        # Internal API for worker service to update pipeline runs
        # These endpoints are authenticated via internal API key
        class PipelineRunsController < InternalBaseController
          before_action :set_pipeline_run

          # GET /api/v1/internal/devops/pipeline_runs/:id
          def show
            render_success({
              pipeline_run: serialize_run_with_steps(@pipeline_run)
            })
          end

          # PATCH /api/v1/internal/devops/pipeline_runs/:id
          def update
            if @pipeline_run.update(run_params)
              render_success({
                pipeline_run: serialize_run(@pipeline_run)
              })
            else
              render_validation_error(@pipeline_run)
            end
          end

          private

          def set_pipeline_run
            @pipeline_run = ::Devops::PipelineRun.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Pipeline run not found", status: :not_found)
          end

          def run_params
            params.require(:pipeline_run).permit(
              :status, :started_at, :completed_at, :error_message,
              outputs: {}, artifacts: {}
            )
          end

          def serialize_run(run)
            {
              id: run.id,
              status: run.status,
              started_at: run.started_at,
              completed_at: run.completed_at,
              duration_seconds: run.duration_seconds,
              error_message: run.error_message,
              progress_percentage: run.progress_percentage
            }
          end

          def serialize_run_with_steps(run)
            result = serialize_run(run)
            result[:pipeline_id] = run.devops_pipeline_id
            result[:pipeline_name] = run.pipeline.name
            result[:trigger_type] = run.trigger_type
            result[:trigger_context] = run.trigger_context
            result[:steps] = run.pipeline.pipeline_steps.where(is_active: true).order(:position).map do |step|
              {
                id: step.id,
                name: step.name,
                step_type: step.step_type,
                position: step.position,
                is_active: step.is_active,
                continue_on_error: step.continue_on_error,
                requires_approval: step.requires_approval,
                configuration: step.configuration
              }
            end
            result
          end
        end
      end
    end
  end
end

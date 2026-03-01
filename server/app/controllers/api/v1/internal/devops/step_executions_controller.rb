# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        # Internal API for worker service to manage step executions
        class StepExecutionsController < InternalBaseController
          before_action :set_step_execution, only: [ :show, :update ]

          # POST /api/v1/internal/devops/step_executions
          def create
            run = ::Devops::PipelineRun.find(params.dig(:step_execution, :pipeline_run_id))
            step = ::Devops::PipelineStep.find(params.dig(:step_execution, :pipeline_step_id))

            execution = run.step_executions.create!(
              pipeline_step: step,
              status: params.dig(:step_execution, :status) || "pending"
            )

            render_success({
              step_execution: serialize_execution(execution)
            }, status: :created)
          rescue ActiveRecord::RecordNotFound => e
            render_error("Record not found: #{e.message}", status: :not_found)
          rescue ActiveRecord::RecordInvalid => e
            render_error("Validation failed: #{e.message}", status: :unprocessable_content)
          end

          # GET /api/v1/internal/devops/step_executions/:id
          def show
            render_success({
              step_execution: serialize_execution(@step_execution)
            })
          end

          # PATCH /api/v1/internal/devops/step_executions/:id
          def update
            if @step_execution.update(execution_params)
              render_success({
                step_execution: serialize_execution(@step_execution)
              })
            else
              render_validation_error(@step_execution)
            end
          end

          private

          def set_step_execution
            @step_execution = ::Devops::StepExecution.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Step execution not found", status: :not_found)
          end

          def execution_params
            params.require(:step_execution).permit(
              :status, :started_at, :completed_at, :error_message,
              :logs, outputs: {}
            )
          end

          def serialize_execution(execution)
            {
              id: execution.id,
              pipeline_run_id: execution.devops_pipeline_run_id,
              pipeline_step_id: execution.devops_pipeline_step_id,
              status: execution.status,
              started_at: execution.started_at,
              completed_at: execution.completed_at,
              duration_seconds: execution.duration_seconds,
              error_message: execution.error_message,
              logs: execution.logs,
              outputs: execution.outputs
            }
          end
        end
      end
    end
  end
end

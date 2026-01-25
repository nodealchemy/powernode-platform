# frozen_string_literal: true

module Api
  module V1
    module Devops
      class PipelinesController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [:index, :show, :export_yaml]
        before_action :require_write_permission, only: [:create, :update, :destroy, :trigger, :duplicate]
        before_action :set_pipeline, only: [:show, :update, :destroy, :trigger, :export_yaml, :duplicate]

        # GET /api/v1/devops/pipelines
        def index
          pipelines = current_user.account.devops_pipelines
                                  .includes(:pipeline_steps, :ai_provider)
                                  .order(created_at: :desc)

          # Filter by active status if provided
          pipelines = pipelines.where(is_active: params[:is_active]) if params[:is_active].present?

          render_success({
            pipelines: serialize_collection(pipelines),
            meta: {
              total: pipelines.count,
              active_count: current_user.account.devops_pipelines.where(is_active: true).count,
              total_runs: current_user.account.devops_pipelines.joins(:runs).count
            }
          })

          log_audit_event("devops.pipelines.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list pipelines: #{e.message}"
          render_error("Failed to list pipelines", status: :internal_server_error)
        end

        # GET /api/v1/devops/pipelines/:id
        def show
          render_success({
            pipeline: serialize_pipeline(@pipeline, include_steps: true, include_recent_runs: params[:include_runs])
          })

          log_audit_event("devops.pipelines.read", @pipeline)
        rescue StandardError => e
          Rails.logger.error "Failed to get pipeline: #{e.message}"
          render_error("Failed to get pipeline", status: :internal_server_error)
        end

        # POST /api/v1/devops/pipelines
        def create
          pipeline = current_user.account.devops_pipelines.new(pipeline_params)
          pipeline.created_by = current_user

          if pipeline.save
            # Create pipeline steps if provided
            create_steps(pipeline, params[:steps]) if params[:steps].present?

            render_success({
              pipeline: serialize_pipeline(pipeline, include_steps: true),
              message: "Pipeline created successfully"
            }, status: :created)

            log_audit_event("devops.pipelines.create", pipeline)
          else
            render_validation_error(pipeline.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to create pipeline: #{e.message}"
          render_error("Failed to create pipeline", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/devops/pipelines/:id
        def update
          if @pipeline.update(pipeline_params)
            # Update pipeline steps if provided
            update_steps(@pipeline, params[:steps]) if params[:steps].present?

            render_success({
              pipeline: serialize_pipeline(@pipeline, include_steps: true),
              message: "Pipeline updated successfully"
            })

            log_audit_event("devops.pipelines.update", @pipeline)
          else
            render_validation_error(@pipeline.errors)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to update pipeline: #{e.message}"
          render_error("Failed to update pipeline", status: :internal_server_error)
        end

        # DELETE /api/v1/devops/pipelines/:id
        def destroy
          # Check for active runs
          if @pipeline.runs.where(status: [:pending, :running]).exists?
            render_error("Cannot delete pipeline with active runs", status: :unprocessable_content)
            return
          end

          @pipeline.destroy!

          render_success({
            message: "Pipeline deleted successfully"
          })

          log_audit_event("devops.pipelines.delete", @pipeline)
        rescue StandardError => e
          Rails.logger.error "Failed to delete pipeline: #{e.message}"
          render_error("Failed to delete pipeline", status: :internal_server_error)
        end

        # POST /api/v1/devops/pipelines/:id/trigger
        # Params:
        #   - context: Hash of trigger context (optional)
        #   - simulate: Boolean to use simulated execution (default: true)
        #   - step_delay: Integer seconds between steps (default: 3)
        #   - fail_step: Integer step position to fail at (optional)
        def trigger
          unless @pipeline.is_active?
            render_error("Cannot trigger inactive pipeline", status: :unprocessable_content)
            return
          end

          run = @pipeline.runs.create!(
            status: :pending,
            trigger_type: :manual,
            trigger_context: params[:context] || {},
            triggered_by: current_user
          )

          # Build execution options
          execution_options = {
            simulate: params.fetch(:simulate, true),
            step_delay: params.fetch(:step_delay, 3).to_i
          }
          execution_options[:fail_step] = params[:fail_step].to_i if params[:fail_step].present?

          # Queue the pipeline execution job via worker service
          worker_queued = false
          worker_error = nil
          begin
            WorkerJobService.enqueue_job(
              "Devops::PipelineExecutionJob",
              args: [run.id, execution_options],
              queue: "devops_high"
            )
            worker_queued = true
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn "Worker service unavailable, pipeline run created but not executing: #{e.message}"
            worker_error = e.message
          end

          message = if worker_queued
                      "Pipeline triggered successfully"
                    else
                      "Pipeline run created but worker service unavailable - run will not execute automatically"
                    end

          render_success({
            pipeline_run: serialize_pipeline_run(run),
            message: message,
            worker_queued: worker_queued,
            worker_error: worker_error
          }, status: :created)

          log_audit_event("devops.pipelines.trigger", @pipeline)
        rescue StandardError => e
          render_internal_error("Failed to trigger pipeline", exception: e)
        end

        # GET /api/v1/devops/pipelines/:id/export_yaml
        def export_yaml
          yaml_content = @pipeline.generate_workflow_yaml

          render_success({
            pipeline_id: @pipeline.id,
            pipeline_name: @pipeline.name,
            yaml: yaml_content,
            generated_at: Time.current
          })

          log_audit_event("devops.pipelines.export_yaml", @pipeline)
        rescue StandardError => e
          render_internal_error("Failed to export pipeline YAML", exception: e)
        end

        # POST /api/v1/devops/pipelines/:id/duplicate
        def duplicate
          new_pipeline = @pipeline.dup
          new_pipeline.name = "#{@pipeline.name} (Copy)"
          new_pipeline.slug = nil # Let the model generate a new slug
          new_pipeline.created_by = current_user

          ActiveRecord::Base.transaction do
            new_pipeline.save!

            # Duplicate steps
            @pipeline.pipeline_steps.each do |step|
              new_step = step.dup
              new_step.pipeline = new_pipeline
              new_step.save!
            end
          end

          render_success({
            pipeline: serialize_pipeline(new_pipeline, include_steps: true),
            message: "Pipeline duplicated successfully"
          }, status: :created)

          log_audit_event("devops.pipelines.duplicate", new_pipeline)
        rescue StandardError => e
          Rails.logger.error "Failed to duplicate pipeline: #{e.message}"
          render_error("Failed to duplicate pipeline", status: :internal_server_error)
        end

        private

        def set_pipeline
          @pipeline = current_user.account.devops_pipelines.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("devops.pipelines.read")

          render_error("Insufficient permissions to view pipelines", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("devops.pipelines.write")

          render_error("Insufficient permissions to manage pipelines", status: :forbidden)
        end

        def pipeline_params
          params.require(:pipeline).permit(
            :name,
            :description,
            :ai_config_id,
            :is_active,
            triggers: {},
            settings: {}
          )
        end

        def create_steps(pipeline, steps_params)
          steps_params.each_with_index do |step_params, index|
            pipeline.pipeline_steps.create!(
              name: step_params[:name],
              step_type: step_params[:step_type],
              position: step_params[:position] || (index + 1),
              configuration: step_params[:configuration] || step_params[:config] || {},
              inputs: step_params[:inputs] || {},
              outputs: step_params[:outputs] || [],
              condition: step_params[:condition],
              continue_on_error: step_params[:continue_on_error] || false,
              is_active: step_params[:is_active] != false,
              shared_prompt_template_id: step_params[:shared_prompt_template_id] || step_params[:prompt_template_id],
              requires_approval: step_params[:requires_approval] || false,
              approval_settings: step_params[:approval_settings] || {}
            )
          end
        end

        def update_steps(pipeline, steps_params)
          # Simple strategy: replace all steps
          pipeline.pipeline_steps.destroy_all
          create_steps(pipeline, steps_params)
        end

        def serialize_collection(pipelines)
          pipelines.map { |p| serialize_pipeline(p) }
        end

        def serialize_pipeline(pipeline, include_steps: false, include_recent_runs: false)
          result = ::Devops::PipelineSerializer.new(pipeline).serializable_hash[:data][:attributes]
          result[:id] = pipeline.id

          if include_steps
            result[:steps] = pipeline.pipeline_steps.order(:position).map do |step|
              ::Devops::PipelineStepSerializer.new(step).serializable_hash[:data][:attributes].merge(id: step.id)
            end
          end

          if include_recent_runs == "true" || include_recent_runs == true
            result[:recent_runs] = pipeline.runs.order(created_at: :desc).limit(5).map do |run|
              serialize_pipeline_run(run)
            end
          end

          result
        end

        def serialize_pipeline_run(run)
          ::Devops::PipelineRunSerializer.new(run).serializable_hash[:data][:attributes].merge(id: run.id)
        end
      end
    end
  end
end

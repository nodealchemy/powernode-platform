# frozen_string_literal: true

module Api
  module V1
    module CiCd
      class SchedulesController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :require_read_permission, only: [:index, :show]
        before_action :require_write_permission, only: [:create, :update, :destroy, :toggle]
        before_action :set_schedule, only: [:show, :update, :destroy, :toggle]

        # GET /api/v1/ci_cd/schedules
        def index
          schedules = ::Devops::Schedule.joins(:pipeline)
                                      .where(ci_cd_pipelines: { account_id: current_user.account_id })
                                      .includes(:pipeline, :created_by)
                                      .order(created_at: :desc)

          # Filter by pipeline if provided
          schedules = schedules.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?

          # Filter by active status if provided
          schedules = schedules.where(is_active: params[:is_active]) if params[:is_active].present?

          render_success({
            schedules: serialize_collection(schedules),
            meta: {
              total: schedules.count,
              active_count: schedules.where(is_active: true).count,
              next_due: schedules.where(is_active: true).order(:next_run_at).first&.next_run_at
            }
          })

          log_audit_event("ci_cd.schedules.list", current_user.account)
        rescue StandardError => e
          Rails.logger.error "Failed to list schedules: #{e.message}"
          render_error("Failed to list schedules", status: :internal_server_error)
        end

        # GET /api/v1/ci_cd/schedules/:id
        def show
          render_success({
            schedule: serialize_schedule(@schedule, include_pipeline: params[:include_pipeline])
          })

          log_audit_event("ci_cd.schedules.read", @schedule)
        rescue StandardError => e
          Rails.logger.error "Failed to get schedule: #{e.message}"
          render_error("Failed to get schedule", status: :internal_server_error)
        end

        # POST /api/v1/ci_cd/schedules
        def create
          # Find pipeline within account scope
          pipeline = current_user.account.ci_cd_pipelines.find(params[:schedule][:pipeline_id])

          schedule = pipeline.schedules.new(schedule_params.except(:pipeline_id))
          schedule.created_by = current_user

          if schedule.save
            render_success({
              schedule: serialize_schedule(schedule),
              message: "Schedule created successfully"
            }, status: :created)

            log_audit_event("ci_cd.schedules.create", schedule)
          else
            render_validation_error(schedule.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to create schedule: #{e.message}"
          render_error("Failed to create schedule", status: :internal_server_error)
        end

        # PATCH/PUT /api/v1/ci_cd/schedules/:id
        def update
          # If changing pipeline, verify it belongs to the account
          if params[:schedule][:pipeline_id].present?
            current_user.account.ci_cd_pipelines.find(params[:schedule][:pipeline_id])
          end

          if @schedule.update(schedule_params)
            render_success({
              schedule: serialize_schedule(@schedule),
              message: "Schedule updated successfully"
            })

            log_audit_event("ci_cd.schedules.update", @schedule)
          else
            render_validation_error(@schedule.errors)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to update schedule: #{e.message}"
          render_error("Failed to update schedule", status: :internal_server_error)
        end

        # DELETE /api/v1/ci_cd/schedules/:id
        def destroy
          @schedule.destroy!

          render_success({
            message: "Schedule deleted successfully"
          })

          log_audit_event("ci_cd.schedules.delete", @schedule)
        rescue StandardError => e
          Rails.logger.error "Failed to delete schedule: #{e.message}"
          render_error("Failed to delete schedule", status: :internal_server_error)
        end

        # POST /api/v1/ci_cd/schedules/:id/toggle
        def toggle
          @schedule.update!(is_active: !@schedule.is_active?)

          render_success({
            schedule: serialize_schedule(@schedule),
            message: @schedule.is_active? ? "Schedule activated" : "Schedule deactivated"
          })

          log_audit_event("ci_cd.schedules.toggle", @schedule)
        rescue StandardError => e
          Rails.logger.error "Failed to toggle schedule: #{e.message}"
          render_error("Failed to toggle schedule", status: :internal_server_error)
        end

        private

        def set_schedule
          @schedule = ::Devops::Schedule.joins(:pipeline)
                                      .where(ci_cd_pipelines: { account_id: current_user.account_id })
                                      .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Schedule not found", status: :not_found)
        end

        def require_read_permission
          return if current_user.has_permission?("ci_cd.schedules.read")

          render_error("Insufficient permissions to view schedules", status: :forbidden)
        end

        def require_write_permission
          return if current_user.has_permission?("ci_cd.schedules.write")

          render_error("Insufficient permissions to manage schedules", status: :forbidden)
        end

        def schedule_params
          params.require(:schedule).permit(
            :name,
            :cron_expression,
            :timezone,
            :is_active,
            :pipeline_id,
            inputs: {}
          )
        end

        def serialize_collection(schedules)
          schedules.map { |s| serialize_schedule(s) }
        end

        def serialize_schedule(schedule, include_pipeline: false)
          result = ::Devops::ScheduleSerializer.new(schedule).serializable_hash[:data][:attributes]
          result[:id] = schedule.id

          if include_pipeline == "true" || include_pipeline == true
            result[:pipeline] = ::Devops::PipelineSerializer.new(schedule.pipeline).serializable_hash[:data][:attributes]
            result[:pipeline][:id] = schedule.pipeline.id
          end

          result
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  module V1
    module Git
      class PipelineSchedulesController < ApplicationController
        before_action :set_repository, only: %i[index create]
        before_action :set_schedule, only: %i[show update destroy trigger pause resume]
        before_action :validate_permissions

        # GET /api/v1/git/repositories/:repository_id/schedules
        def index
          schedules = @repository.git_pipeline_schedules

          # Filters
          schedules = schedules.active if params[:active] == "true"
          schedules = schedules.inactive if params[:active] == "false"
          schedules = schedules.by_status(params[:status]) if params[:status].present?

          # Sorting
          case params[:sort]
          when "name"
            schedules = schedules.order(name: params[:direction] == "desc" ? :desc : :asc)
          when "next_run"
            schedules = schedules.order(next_run_at: params[:direction] == "desc" ? :desc : :asc)
          when "last_run"
            schedules = schedules.order(last_run_at: params[:direction] == "desc" ? :desc : :asc)
          else
            schedules = schedules.order(created_at: :desc)
          end

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          total_count = schedules.count
          schedules = schedules.offset((page - 1) * per_page).limit(per_page)

          render_success({
            schedules: schedules.map { |s| serialize_schedule(s) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_count: total_count,
              total_pages: (total_count.to_f / per_page).ceil
            }
          })
        end

        # GET /api/v1/git/pipeline_schedules/:id
        def show
          render_success({ schedule: serialize_schedule_detail(@schedule) })
        end

        # POST /api/v1/git/repositories/:repository_id/schedules
        def create
          schedule = @repository.git_pipeline_schedules.build(schedule_params)
          schedule.account = current_user.account
          schedule.created_by = current_user

          if schedule.save
            render_success({ schedule: serialize_schedule_detail(schedule) }, status: :created)
          else
            render_validation_error(schedule)
          end
        end

        # PUT /api/v1/git/pipeline_schedules/:id
        def update
          if @schedule.update(schedule_params)
            render_success({ schedule: serialize_schedule_detail(@schedule) })
          else
            render_validation_error(@schedule)
          end
        end

        # DELETE /api/v1/git/pipeline_schedules/:id
        def destroy
          @schedule.destroy
          render_success(message: "Schedule deleted successfully")
        end

        # POST /api/v1/git/pipeline_schedules/:id/trigger
        def trigger
          credential = @schedule.git_provider_credential
          return render_error("Credential not available", status: :unprocessable_entity) unless credential&.can_be_used?

          repository = @schedule.git_repository
          client = ::Git::ApiClient.for(credential)

          result = trigger_pipeline(client, repository, @schedule)

          if result[:success]
            @schedule.update!(last_run_at: Time.current, run_count: @schedule.run_count + 1)
            render_success({
              message: "Pipeline triggered successfully",
              pipeline_id: result[:pipeline_id]
            })
          else
            render_error(result[:error] || "Failed to trigger pipeline", status: :unprocessable_entity)
          end
        end

        # POST /api/v1/git/pipeline_schedules/:id/pause
        def pause
          @schedule.deactivate!
          render_success({ schedule: serialize_schedule_detail(@schedule) })
        end

        # POST /api/v1/git/pipeline_schedules/:id/resume
        def resume
          @schedule.activate!
          render_success({ schedule: serialize_schedule_detail(@schedule) })
        end

        private

        def set_repository
          @repository = current_user.account.git_repositories.find(params[:repository_id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Repository")
        end

        def set_schedule
          @schedule = ::Git::PipelineSchedule.where(account: current_user.account).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Schedule")
        end

        def validate_permissions
          case action_name.to_sym
          when :index, :show
            return if current_user.has_permission?("git.schedules.read")
          when :create, :update, :destroy, :trigger, :pause, :resume
            return if current_user.has_permission?("git.schedules.manage")
          end

          render_forbidden
        end

        def schedule_params
          params.require(:schedule).permit(
            :name, :description, :cron_expression, :timezone, :ref,
            :workflow_file, :is_active, inputs: {}
          )
        end

        def trigger_pipeline(client, repository, schedule)
          case schedule.git_provider&.provider_type
          when "github"
            result = client.trigger_workflow(
              repository.owner,
              repository.name,
              schedule.workflow_file || ".github/workflows/ci.yml",
              schedule.ref,
              schedule.inputs
            )
            { success: result[:success] != false, pipeline_id: result[:id], error: result[:error] }
          when "gitea"
            result = client.trigger_workflow(
              repository.owner,
              repository.name,
              schedule.workflow_file || ".gitea/workflows/ci.yml",
              schedule.ref,
              schedule.inputs
            )
            { success: result[:success] != false, pipeline_id: result[:id], error: result[:error] }
          else
            { success: false, error: "Unsupported provider" }
          end
        rescue StandardError => e
          { success: false, error: e.message }
        end

        def serialize_schedule(schedule)
          {
            id: schedule.id,
            name: schedule.name,
            cron_expression: schedule.cron_expression,
            timezone: schedule.timezone,
            ref: schedule.ref,
            workflow_file: schedule.workflow_file,
            is_active: schedule.is_active,
            next_run_at: schedule.next_run_at&.iso8601,
            last_run_at: schedule.last_run_at&.iso8601,
            last_run_status: schedule.last_run_status,
            run_count: schedule.run_count,
            success_rate: schedule.success_rate,
            repository_id: schedule.git_repository_id
          }
        end

        def serialize_schedule_detail(schedule)
          serialize_schedule(schedule).merge(
            description: schedule.description,
            inputs: schedule.inputs,
            success_count: schedule.success_count,
            failure_count: schedule.failure_count,
            consecutive_failures: schedule.consecutive_failures,
            human_schedule: schedule.human_schedule,
            next_runs: schedule.next_runs(5).map(&:iso8601),
            overdue: schedule.overdue?,
            last_pipeline_id: schedule.last_pipeline_id,
            created_by_id: schedule.created_by_id,
            repository: {
              id: schedule.git_repository.id,
              name: schedule.git_repository.name,
              full_name: schedule.git_repository.full_name
            },
            created_at: schedule.created_at.iso8601,
            updated_at: schedule.updated_at.iso8601
          )
        end
      end
    end
  end
end

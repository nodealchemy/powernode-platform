# frozen_string_literal: true

module Api
  module V1
    module Git
      class PipelinesController < ApplicationController
        before_action :set_pipeline, only: %i[show cancel retry jobs]
        before_action :set_repository_for_trigger, only: %i[trigger]
        before_action :validate_permissions

        # GET /api/v1/git/pipelines
        def index
          pipelines = current_user.account.git_pipelines.includes(:jobs, :repository)

          # Filter by repository
          if params[:repository_id].present?
            pipelines = pipelines.where(git_repository_id: params[:repository_id])
          end

          # Filter by status - support both "running" alias and "in_progress"
          if params[:status].present?
            status = params[:status] == "running" ? "in_progress" : params[:status]
            pipelines = pipelines.where(status: status)
          end

          pipelines = pipelines.where(conclusion: params[:conclusion]) if params[:conclusion].present?
          pipelines = pipelines.by_ref(params[:ref]) if params[:ref].present?

          # Pagination
          page = [ params[:page].to_i, 1 ].max
          per_page = [ [ params[:per_page].to_i, 50 ].min, 20 ].max
          total = pipelines.count
          pipelines = pipelines.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

          render_success({
            items: pipelines.map { |p| serialize_pipeline(p) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total
            }
          })
        end

        # GET /api/v1/git/pipelines/:id
        def show
          render_success({ pipeline: serialize_pipeline_detail(@pipeline) })
        end

        # POST /api/v1/git/repositories/:repository_id/pipelines/trigger
        def trigger
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          ref = params[:ref] || @repository.default_branch
          inputs = params[:inputs]&.to_unsafe_h || {}
          workflow_id = params[:workflow] || params[:workflow_id] || params[:workflow_file]

          result = client.trigger_workflow(
            @repository.owner,
            @repository.name,
            workflow_id,
            ref,
            inputs
          )

          if result[:success]
            render_success(
              { message: "Pipeline triggered successfully", pipeline_id: result[:pipeline_id] },
              status: :accepted
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/git/pipelines/:id/cancel
        def cancel
          unless @pipeline.active?
            return render_error("Pipeline is not running", status: :unprocessable_content)
          end

          repository = @pipeline.git_repository
          credential = repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          result = client.cancel_workflow_run(repository.owner, repository.name, @pipeline.external_id)

          if result[:success]
            @pipeline.cancel!
            render_success(message: "Pipeline cancelled successfully")
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/git/pipelines/:id/retry
        def retry
          if @pipeline.successful?
            return render_error("Cannot retry successful pipeline", status: :unprocessable_content)
          end

          repository = @pipeline.git_repository
          credential = repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          result = client.rerun_workflow(repository.owner, repository.name, @pipeline.external_id)

          if result[:success]
            # Sync the new pipeline run
            begin
              WorkerApiClient.new.queue_git_pipeline_sync(repository.id, result[:pipeline_id])
            rescue WorkerApiClient::ApiError => e
              Rails.logger.warn "Failed to queue pipeline sync job: #{e.message}"
            end
            render_success(
              { message: "Pipeline retry initiated", new_pipeline_id: result[:pipeline_id] },
              status: :accepted
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue ::Devops::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/pipelines/:id/jobs
        def jobs
          pipeline_jobs = @pipeline.git_pipeline_jobs.order(:step_number)

          render_success({
            jobs: pipeline_jobs.map { |j| serialize_job(j) },
            count: pipeline_jobs.count
          })
        end

        # GET /api/v1/git/pipelines/:pipeline_id/jobs/:id/logs
        def job_logs
          pipeline = current_user.account.git_pipelines.find(params[:pipeline_id])
          job = pipeline.git_pipeline_jobs.find(params[:id])

          # Check if user has logs permission
          unless current_user.has_permission?("git.pipelines.logs")
            return render_error("You don't have permission to view logs", status: :forbidden)
          end

          logs = job.logs_content || job.fetch_logs!

          if logs
            render_success({
              job_id: job.id,
              logs: logs,
              is_complete: job.finished?
            })
          else
            render_error("Logs not available", status: :not_found)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Job not found", status: :not_found)
        end

        # GET /api/v1/git/pipelines/stats
        def stats
          pipelines = current_user.account.git_pipelines

          # Filter by repository if specified
          if params[:repository_id].present?
            pipelines = pipelines.where(git_repository_id: params[:repository_id])
          end

          total = pipelines.count
          successful = pipelines.successful.count

          render_success({
            stats: {
              total_runs: total,
              success_count: successful,
              failed_count: pipelines.where(conclusion: "failure").count,
              cancelled_count: pipelines.where(conclusion: "cancelled").count,
              success_rate: total.positive? ? (successful.to_f / total * 100).round(2) : 0,
              avg_duration_seconds: pipelines.where.not(duration_seconds: nil).average(:duration_seconds)&.to_i || 0,
              runs_today: pipelines.where("created_at >= ?", Time.current.beginning_of_day).count,
              runs_this_week: pipelines.where("created_at >= ?", Time.current.beginning_of_week).count,
              active_runs: pipelines.active.count
            }
          })
        end

        private

        def set_pipeline
          @pipeline = current_user.account.git_pipelines
                        .includes(:jobs, :repository)
                        .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Pipeline not found", status: :not_found)
        end

        def set_repository_for_trigger
          @repository = current_user.account.git_repositories
                          .includes(:credential)
                          .find(params[:repository_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Repository not found", status: :not_found)
        end

        def validate_permissions
          case action_name
          when "index", "show", "jobs", "stats"
            require_permission("git.pipelines.read")
          when "trigger", "retry"
            require_permission("git.pipelines.trigger")
          when "cancel"
            require_permission("git.pipelines.cancel")
          when "job_logs"
            require_permission("git.pipelines.logs")
          end
        end

        def serialize_pipeline(pipeline)
          {
            id: pipeline.id,
            external_id: pipeline.external_id,
            name: pipeline.name,
            status: pipeline.status,
            conclusion: pipeline.conclusion,
            trigger_event: pipeline.trigger_event,
            ref: pipeline.ref,
            branch_name: pipeline.branch_name,
            sha: pipeline.sha,
            short_sha: pipeline.short_sha,
            actor_username: pipeline.actor_username,
            web_url: pipeline.web_url,
            run_number: pipeline.run_number,
            run_attempt: pipeline.run_attempt,
            total_jobs: pipeline.total_jobs,
            completed_jobs: pipeline.completed_jobs,
            failed_jobs: pipeline.failed_jobs,
            progress_percentage: pipeline.progress_percentage,
            duration_seconds: pipeline.duration_seconds,
            duration_formatted: pipeline.duration_formatted,
            started_at: pipeline.started_at&.iso8601,
            completed_at: pipeline.completed_at&.iso8601,
            created_at: pipeline.created_at.iso8601,
            repository_id: pipeline.git_repository_id
          }
        end

        def serialize_pipeline_detail(pipeline)
          serialize_pipeline(pipeline).merge(
            jobs: pipeline.git_pipeline_jobs.order(:step_number).map { |j| serialize_job(j) },
            workflow_config: pipeline.workflow_config,
            metadata: pipeline.metadata
          )
        end

        def serialize_job(job)
          {
            id: job.id,
            external_id: job.external_id,
            name: job.name,
            status: job.status,
            conclusion: job.conclusion,
            step_number: job.step_number,
            runner_name: job.runner_name,
            runner_os: job.runner_os,
            duration_seconds: job.duration_seconds,
            duration_formatted: job.duration_formatted,
            logs_available: job.logs_available?,
            completed_steps: job.completed_steps_count,
            total_steps: job.total_steps_count,
            started_at: job.started_at&.iso8601,
            completed_at: job.completed_at&.iso8601,
            created_at: job.created_at.iso8601
          }
        end
      end
    end
  end
end

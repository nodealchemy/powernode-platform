# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        class PipelinesController < InternalBaseController
          before_action :set_pipeline

          # GET /api/v1/internal/git/pipelines/:id
          def show
            render json: {
              success: true,
              data: serialize_pipeline(@pipeline)
            }
          end

          # PATCH /api/v1/internal/git/pipelines/:id
          def update
            if @pipeline.update(pipeline_params)
              render json: { success: true, data: serialize_pipeline(@pipeline) }
            else
              render json: { success: false, error: @pipeline.errors.full_messages.join(", ") },
                     status: :unprocessable_content
            end
          end

          # POST /api/v1/internal/git/pipelines/:id/sync_jobs
          def sync_jobs
            jobs_data = params[:jobs] || []
            synced = []

            jobs_data.each do |job_data|
              job = @pipeline.git_pipeline_jobs.find_or_initialize_by(
                external_id: job_data[:external_id]
              )

              job.assign_attributes(
                account: @pipeline.account,
                name: job_data[:name],
                status: job_data[:status],
                conclusion: job_data[:conclusion],
                step_number: job_data[:step_number],
                runner_name: job_data[:runner_name],
                runner_id: job_data[:runner_id],
                runner_os: job_data[:runner_os],
                logs_url: job_data[:logs_url],
                logs_content: job_data[:logs_content],
                duration_seconds: job_data[:duration_seconds],
                steps: job_data[:steps],
                outputs: job_data[:outputs],
                started_at: job_data[:started_at],
                completed_at: job_data[:completed_at]
              )

              synced << job if job.save
            end

            # Update pipeline job counts
            @pipeline.update_job_counts!

            render json: {
              success: true,
              data: {
                pipeline_id: @pipeline.id,
                synced_count: synced.count,
                job_ids: synced.map(&:id)
              }
            }
          end

          private

          def set_pipeline
            @pipeline = ::Git::Pipeline.includes(:repository, :jobs).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: "Pipeline not found" },
                   status: :not_found
          end

          def pipeline_params
            params.permit(
              :status, :conclusion, :total_jobs, :completed_jobs, :failed_jobs,
              :duration_seconds, :started_at, :completed_at,
              workflow_config: {}, metadata: {}
            )
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
              sha: pipeline.sha,
              actor_username: pipeline.actor_username,
              web_url: pipeline.web_url,
              logs_url: pipeline.logs_url,
              run_number: pipeline.run_number,
              run_attempt: pipeline.run_attempt,
              total_jobs: pipeline.total_jobs,
              completed_jobs: pipeline.completed_jobs,
              failed_jobs: pipeline.failed_jobs,
              duration_seconds: pipeline.duration_seconds,
              workflow_config: pipeline.workflow_config,
              metadata: pipeline.metadata,
              started_at: pipeline.started_at&.iso8601,
              completed_at: pipeline.completed_at&.iso8601,
              created_at: pipeline.created_at.iso8601,
              account_id: pipeline.account_id,
              repository: {
                id: pipeline.git_repository.id,
                name: pipeline.git_repository.name,
                full_name: pipeline.git_repository.full_name,
                owner: pipeline.git_repository.owner,
                credential_id: pipeline.git_repository.git_provider_credential_id
              },
              jobs: pipeline.git_pipeline_jobs.map { |job| serialize_job(job) }
            }
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
              logs_available: job.logs_available?,
              started_at: job.started_at&.iso8601,
              completed_at: job.completed_at&.iso8601
            }
          end
        end
      end
    end
  end
end

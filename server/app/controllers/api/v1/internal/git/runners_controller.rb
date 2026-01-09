# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        class RunnersController < InternalBaseController
          # POST /api/v1/internal/git/runners/sync
          # Sync runners from worker job
          def sync
            credential = ::Git::ProviderCredential.find(params[:credential_id])
            repository = params[:repository_id].present? ? ::Git::Repository.find(params[:repository_id]) : nil
            runners_data = params[:runners] || []

            synced_runners = []

            runners_data.each do |runner_data|
              runner = ::Git::Runner.sync_from_provider(
                credential,
                runner_data.to_unsafe_h,
                scope: "repository",
                repository: repository
              )
              synced_runners << serialize_runner(runner) if runner
            end

            render_success({
              synced_count: synced_runners.count,
              runners: synced_runners
            })
          rescue ActiveRecord::RecordNotFound => e
            render_not_found("Credential or Repository")
          rescue StandardError => e
            Rails.logger.error "Failed to sync runners: #{e.message}"
            render_error(e.message, status: :internal_server_error)
          end

          # PUT /api/v1/internal/git/runners/:id/status
          # Update runner status from worker job
          def update_status
            runner = ::Git::Runner.find(params[:id])

            runner.update!(
              status: params[:status],
              busy: params[:busy],
              last_seen_at: params[:last_seen_at] || Time.current
            )

            render_success({ runner: serialize_runner(runner) })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Runner")
          end

          # POST /api/v1/internal/git/runners/:id/job_completed
          # Record job completion metrics
          def job_completed
            runner = ::Git::Runner.find(params[:id])

            if params[:success]
              runner.record_success!
            else
              runner.record_failure!
            end

            render_success({ runner: serialize_runner(runner) })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Runner")
          end

          private

          def serialize_runner(runner)
            {
              id: runner.id,
              external_id: runner.external_id,
              name: runner.name,
              status: runner.status,
              busy: runner.busy,
              runner_scope: runner.runner_scope,
              labels: runner.labels,
              os: runner.os,
              architecture: runner.architecture,
              version: runner.version,
              success_rate: runner.success_rate,
              total_jobs_run: runner.total_jobs_run,
              last_seen_at: runner.last_seen_at&.iso8601,
              credential_id: runner.git_provider_credential_id,
              repository_id: runner.git_repository_id
            }
          end
        end
      end
    end
  end
end

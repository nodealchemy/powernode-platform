# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        class RepositoriesController < InternalBaseController
          before_action :set_repository, except: [ :create ]
          before_action :validate_internal_permissions

          # POST /api/v1/internal/git/repositories
          # Upsert a repository from worker sync
          def create
            credential = ::Devops::GitProviderCredential.find_by(id: params[:credential_id])
            unless credential
              render_error("Credential not found", status: :not_found)
              return
            end

            repo_params = params[:repository] || {}
            external_id = repo_params[:external_id]

            # Find or initialize repository by external_id and credential
            repository = credential.repositories.find_or_initialize_by(
              external_id: external_id
            )

            # Build languages hash from primary_language if provided
            languages = {}
            languages[repo_params[:primary_language]] = 100 if repo_params[:primary_language].present?

            repository.assign_attributes(
              account: credential.account,
              name: repo_params[:name],
              full_name: repo_params[:full_name],
              owner: repo_params[:owner],
              description: repo_params[:description],
              default_branch: repo_params[:default_branch] || "main",
              clone_url: repo_params[:clone_url],
              ssh_url: repo_params[:ssh_url],
              web_url: repo_params[:web_url],
              is_private: repo_params[:is_private] || false,
              is_fork: repo_params[:is_fork] || false,
              is_archived: repo_params[:is_archived] || false,
              stars_count: repo_params[:stars_count] || 0,
              forks_count: repo_params[:forks_count] || 0,
              open_issues_count: repo_params[:open_issues_count] || 0,
              languages: languages.presence || repo_params[:languages] || {},
              topics: repo_params[:topics] || [],
              last_synced_at: repo_params[:last_synced_at] || Time.current
            )

            if repository.save
              render_success({
                **serialize_repository(repository),
                created: repository.previously_new_record?
              })
            else
              render_validation_error(repository)
            end
          end

          # GET /api/v1/internal/git/repositories/:id
          def show
            render_success(serialize_repository(@repository))
          end

          # PATCH /api/v1/internal/git/repositories/:id
          def update
            if @repository.update(repository_params)
              render_success(serialize_repository(@repository))
            else
              render_validation_error(@repository)
            end
          end

          # POST /api/v1/internal/git/repositories/:id/sync_branches
          def sync_branches
            # Worker can sync branches data
            branches_data = params[:branches] || []

            render_success({
              repository_id: @repository.id,
              synced_count: branches_data.count
            })
          end

          # POST /api/v1/internal/git/repositories/:id/sync_commits
          def sync_commits
            # Worker can sync commits data
            commits_data = params[:commits] || []

            render_success({
              repository_id: @repository.id,
              synced_count: commits_data.count
            })
          end

          # POST /api/v1/internal/git/repositories/:id/sync_pipelines
          def sync_pipelines
            pipelines_data = params[:pipelines] || []
            synced = []

            pipelines_data.each do |pipeline_data|
              pipeline = @repository.pipelines.find_or_initialize_by(
                external_id: pipeline_data[:external_id]
              )

              pipeline.assign_attributes(
                account: @repository.account,
                name: pipeline_data[:name],
                status: pipeline_data[:status],
                conclusion: pipeline_data[:conclusion],
                trigger_event: pipeline_data[:trigger_event],
                ref: pipeline_data[:ref],
                sha: pipeline_data[:sha],
                actor_username: pipeline_data[:actor_username],
                web_url: pipeline_data[:web_url],
                logs_url: pipeline_data[:logs_url],
                run_number: pipeline_data[:run_number],
                run_attempt: pipeline_data[:run_attempt],
                total_jobs: pipeline_data[:total_jobs],
                completed_jobs: pipeline_data[:completed_jobs],
                failed_jobs: pipeline_data[:failed_jobs],
                duration_seconds: pipeline_data[:duration_seconds],
                workflow_config: pipeline_data[:workflow_config],
                started_at: pipeline_data[:started_at],
                completed_at: pipeline_data[:completed_at]
              )

              synced << pipeline if pipeline.save
            end

            render_success({
              repository_id: @repository.id,
              synced_count: synced.count,
              pipeline_ids: synced.map(&:id)
            })
          end

          private

          def set_repository
            @repository = ::Devops::GitRepository.includes(:credential, credential: :provider)
                                       .find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_error("Repository not found", status: :not_found)
          end

          def repository_params
            params.permit(
              :last_synced_at, :last_commit_at,
              :open_issues_count, :open_prs_count,
              :stars_count, :forks_count,
              languages: {}, topics: []
            )
          end

          def validate_internal_permissions
            # Internal API is only accessible via internal token from worker
            # The InternalBaseController already validates the internal token
            # This adds an extra layer of validation for git-specific operations
            return if internal_request?

            render_error("Unauthorized internal access", status: :forbidden)
          end

          def internal_request?
            # Check if request came through internal authentication
            # InternalBaseController sets this based on valid internal token
            request.env["powernode.internal_request"] == true ||
              request.headers["X-Internal-Token"].present?
          end

          def serialize_repository(repo)
            {
              id: repo.id,
              external_id: repo.external_id,
              name: repo.name,
              full_name: repo.full_name,
              owner: repo.owner,
              description: repo.description,
              default_branch: repo.default_branch,
              clone_url: repo.clone_url,
              ssh_url: repo.ssh_url,
              web_url: repo.web_url,
              is_private: repo.is_private,
              webhook_configured: repo.webhook_configured,
              webhook_id: repo.webhook_id,
              last_synced_at: repo.last_synced_at&.iso8601,
              last_commit_at: repo.last_commit_at&.iso8601,
              account_id: repo.account_id,
              credential: {
                id: repo.git_provider_credential.id,
                provider_type: repo.git_provider_credential.provider_type,
                provider: {
                  id: repo.git_provider_credential.git_provider.id,
                  api_base_url: repo.git_provider_credential.git_provider.api_base_url
                }
              }
            }
          end
        end
      end
    end
  end
end

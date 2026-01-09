# frozen_string_literal: true

module Api
  module V1
    module Git
      class RepositoriesController < ApplicationController
        before_action :set_repository, only: %i[
          show destroy
          configure_webhook remove_webhook
          branches commits commit commit_diff compare
          pull_requests issues pipelines
          file_content tree tags
        ]
        before_action :validate_permissions

        # GET /api/v1/git/repositories
        def index
          repositories = current_user.account.git_repositories
                          .includes(:credential, credential: :provider)

          # Apply filters
          repositories = apply_filters(repositories)

          # Pagination
          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 100].min, 20].max
          total = repositories.count
          repositories = repositories.offset((page - 1) * per_page).limit(per_page)

          render_success({
            repositories: repositories.map { |r| serialize_repository(r) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total
            }
          })
        end

        # GET /api/v1/git/repositories/:id
        def show
          render_success({ repository: serialize_repository_detail(@repository) })
        end

        # DELETE /api/v1/git/repositories/:id
        def destroy
          if @repository.destroy
            render_success(message: "Repository removed successfully")
          else
            render_validation_error(@repository.errors)
          end
        end

        # POST /api/v1/git/repositories/sync
        def sync
          credential = current_user.account.git_provider_credentials.find(params[:credential_id])

          # Queue the sync job via worker API
          begin
            WorkerApiClient.new.queue_git_repository_sync(credential.id)
            render_success(
              { message: "Repository sync has been queued" },
              status: :accepted
            )
          rescue WorkerApiClient::ApiError => e
            Rails.logger.error "Failed to queue repository sync: #{e.message}"
            render_error("Failed to queue sync job: #{e.message}", status: :service_unavailable)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Credential not found", status: :not_found)
        end

        # POST /api/v1/git/repositories/:id/configure_webhook
        def configure_webhook
          result = @repository.configure_webhook!

          if result[:success]
            render_success({
              repository: serialize_repository(@repository.reload),
              message: result[:already_configured] ? "Webhook already configured" : "Webhook configured successfully"
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/git/repositories/:id/remove_webhook
        def remove_webhook
          result = @repository.remove_webhook!

          if result[:success]
            render_success({
              repository: serialize_repository(@repository.reload),
              message: "Webhook removed successfully"
            })
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # GET /api/v1/git/repositories/:id/branches
        def branches
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Git::ApiClient.for(credential)
          branches = client.list_branches(@repository.owner, @repository.name, branch_params)

          render_success({ branches: branches })
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/commits
        def commits
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Git::ApiClient.for(credential)
          options = commit_params.to_h.symbolize_keys
          options[:sha] = params[:branch] if params[:branch].present?
          commits = client.list_commits(@repository.owner, @repository.name, options)

          render_success({ commits: commits })
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/pull_requests
        def pull_requests
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Git::ApiClient.for(credential)
          prs = client.list_pull_requests(@repository.owner, @repository.name, pr_params)

          render_success({ pull_requests: prs })
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/issues
        def issues
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Git::ApiClient.for(credential)
          issues = client.list_issues(@repository.owner, @repository.name, issue_params)

          render_success({ issues: issues })
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/pipelines
        def pipelines
          pipelines = @repository.pipelines
                        .order(created_at: :desc)

          # Apply filters
          pipelines = pipelines.where(status: params[:status]) if params[:status].present?
          pipelines = pipelines.where(conclusion: params[:conclusion]) if params[:conclusion].present?
          pipelines = pipelines.where(ref: params[:ref]) if params[:ref].present?

          # Pagination
          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 100].min, 10].max
          total = pipelines.count
          pipelines = pipelines.offset((page - 1) * per_page).limit(per_page)

          # Calculate stats with a single optimized query to prevent N+1
          base_pipelines = @repository.pipelines
          stats_data = base_pipelines.select(
            "COUNT(*) as total_runs",
            "COUNT(CASE WHEN conclusion = 'success' THEN 1 END) as success_count",
            "COUNT(CASE WHEN conclusion = 'failure' THEN 1 END) as failed_count",
            "COUNT(CASE WHEN conclusion = 'cancelled' THEN 1 END) as cancelled_count",
            "AVG(duration_seconds) FILTER (WHERE duration_seconds IS NOT NULL) as avg_duration",
            "COUNT(CASE WHEN created_at >= '#{Time.current.beginning_of_day.iso8601}' THEN 1 END) as runs_today",
            "COUNT(CASE WHEN created_at >= '#{1.week.ago.iso8601}' THEN 1 END) as runs_this_week",
            "COUNT(CASE WHEN status IN ('running', 'pending', 'queued') THEN 1 END) as active_runs"
          ).to_a.first

          total_runs = stats_data[:total_runs].to_i
          stats = {
            total_runs: total_runs,
            success_count: stats_data[:success_count].to_i,
            failed_count: stats_data[:failed_count].to_i,
            cancelled_count: stats_data[:cancelled_count].to_i,
            success_rate: total_runs > 0 ? (stats_data[:success_count].to_f / total_runs * 100).round : 0,
            avg_duration_seconds: stats_data[:avg_duration]&.to_i || 0,
            runs_today: stats_data[:runs_today].to_i,
            runs_this_week: stats_data[:runs_this_week].to_i,
            active_runs: stats_data[:active_runs].to_i
          }

          render_success({
            pipelines: pipelines.map { |p| serialize_pipeline(p) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total
            },
            stats: stats
          })
        end

        # GET /api/v1/git/repositories/:id/commits/:sha
        def commit
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          sha = params[:sha]
          return render_error("SHA is required", status: :bad_request) if sha.blank?

          client = ::Git::ApiClient.for(credential)
          commit_detail = client.get_commit(@repository.owner, @repository.name, sha)

          render_success({ commit: commit_detail })
        rescue ::Git::ApiClient::NotFoundError
          render_error("Commit not found", status: :not_found)
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/commits/:sha/diff
        def commit_diff
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          sha = params[:sha]
          return render_error("SHA is required", status: :bad_request) if sha.blank?

          client = ::Git::ApiClient.for(credential)
          diff = client.get_commit_diff(@repository.owner, @repository.name, sha)

          render_success({ diff: diff })
        rescue ::Git::ApiClient::NotFoundError
          render_error("Commit not found", status: :not_found)
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/compare/:base...:head
        def compare
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          base = params[:base]
          head = params[:head]
          return render_error("Base and head are required", status: :bad_request) if base.blank? || head.blank?

          client = ::Git::ApiClient.for(credential)
          comparison = client.compare_commits(@repository.owner, @repository.name, base, head)

          render_success({ comparison: comparison })
        rescue ::Git::ApiClient::NotFoundError
          render_error("One or more commits not found", status: :not_found)
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/contents/*path
        def file_content
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          path = params[:path]
          return render_error("Path is required", status: :bad_request) if path.blank?

          ref = params[:ref] || @repository.default_branch

          client = ::Git::ApiClient.for(credential)
          content = client.get_file_content(@repository.owner, @repository.name, path, ref)

          if content.nil?
            render_error("File not found", status: :not_found)
          else
            render_success({ content: content })
          end
        rescue ::Git::ApiClient::NotFoundError
          render_error("File not found", status: :not_found)
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/tree/:sha
        def tree
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          sha = params[:sha] || @repository.default_branch
          recursive = params[:recursive] == "true"

          client = ::Git::ApiClient.for(credential)
          tree_data = client.get_tree(@repository.owner, @repository.name, sha, recursive: recursive)

          render_success({ tree: tree_data, commit_sha: sha, path: params[:path] || "" })
        rescue ::Git::ApiClient::NotFoundError
          render_error("Tree not found", status: :not_found)
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/git/repositories/:id/tags
        def tags
          credential = @repository.git_provider_credential
          return render_error("Credential cannot be used", status: :unprocessable_content) unless credential.can_be_used?

          client = ::Git::ApiClient.for(credential)
          tags_list = client.list_tags(@repository.owner, @repository.name, tag_params)

          render_success({ tags: tags_list })
        rescue ::Git::ApiClient::ApiError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def set_repository
          @repository = current_user.account.git_repositories
                          .includes(:credential, credential: :provider)
                          .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Repository not found", status: :not_found)
        end

        def validate_permissions
          case action_name
          when "index", "show", "branches", "commits", "commit", "commit_diff", "compare", "pull_requests", "issues", "file_content", "tree", "tags"
            require_permission("git.repositories.read")
          when "pipelines"
            require_permission("git.pipelines.read")
          when "destroy"
            require_permission("git.repositories.delete")
          when "sync"
            require_permission("git.repositories.sync")
          when "configure_webhook", "remove_webhook"
            require_permission("git.repositories.webhooks.manage")
          end
        end

        def apply_filters(repositories)
          if params[:search].present?
            search = "%#{params[:search]}%"
            repositories = repositories.where(
              "name ILIKE ? OR full_name ILIKE ? OR owner ILIKE ?",
              search, search, search
            )
          end

          if params[:provider_id].present?
            repositories = repositories.joins(:git_provider_credential)
                            .where(git_provider_credentials: { git_provider_id: params[:provider_id] })
          end

          if params[:credential_id].present?
            repositories = repositories.where(git_provider_credential_id: params[:credential_id])
          end

          # Support both visibility and is_private
          if params[:visibility].present?
            is_private = params[:visibility] == "private"
            repositories = repositories.where(is_private: is_private)
          elsif params[:is_private].present?
            repositories = repositories.where(is_private: params[:is_private])
          end

          repositories = repositories.where(webhook_configured: params[:webhook_configured]) if params[:webhook_configured].present?
          repositories = repositories.where(is_archived: params[:is_archived]) if params[:is_archived].present?

          if params[:language].present?
            repositories = repositories.by_language(params[:language])
          end

          # Sorting
          sort_by = params[:sort_by]&.to_sym || :updated_at
          sort_order = params[:sort_order]&.to_sym || :desc
          valid_sorts = %i[name full_name updated_at created_at stars_count last_synced_at]

          if valid_sorts.include?(sort_by)
            repositories = repositories.order(sort_by => sort_order)
          else
            repositories = repositories.order(updated_at: :desc)
          end

          repositories
        end

        def branch_params
          params.permit(:page, :per_page)
        end

        def commit_params
          params.permit(:page, :per_page, :sha, :since, :until, :branch)
        end

        def pr_params
          params.permit(:page, :per_page, :state)
        end

        def issue_params
          params.permit(:page, :per_page, :state)
        end

        def tag_params
          params.permit(:page, :per_page)
        end

        def serialize_repository(repo)
          {
            id: repo.id,
            name: repo.name,
            full_name: repo.full_name,
            owner: repo.owner,
            description: repo.description,
            default_branch: repo.default_branch,
            web_url: repo.web_url,
            is_private: repo.is_private,
            is_fork: repo.is_fork,
            is_archived: repo.is_archived,
            webhook_configured: repo.webhook_configured,
            stars_count: repo.stars_count,
            forks_count: repo.forks_count,
            open_issues_count: repo.open_issues_count,
            open_prs_count: repo.open_prs_count,
            primary_language: repo.primary_language,
            topics: repo.topics,
            last_synced_at: repo.last_synced_at&.iso8601,
            last_commit_at: repo.last_commit_at&.iso8601,
            created_at: repo.created_at.iso8601,
            provider_type: repo.provider_type,
            credential_id: repo.git_provider_credential_id
          }
        end

        def serialize_repository_detail(repo)
          serialize_repository(repo).merge(
            clone_url: repo.clone_url,
            ssh_url: repo.ssh_url,
            languages: repo.languages,
            sync_settings: repo.sync_settings,
            webhook_id: repo.webhook_id,
            provider_created_at: repo.provider_created_at&.iso8601,
            provider_updated_at: repo.provider_updated_at&.iso8601,
            pipeline_stats: repo.pipeline_stats,
            credential: {
              id: repo.git_provider_credential.id,
              name: repo.git_provider_credential.name,
              provider_name: repo.git_provider_credential.git_provider.name
            }
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
            branch_name: pipeline.ref&.sub(%r{^refs/heads/}, ""),
            sha: pipeline.sha,
            short_sha: pipeline.sha&.first(7),
            actor_username: pipeline.actor_username,
            web_url: pipeline.web_url,
            logs_url: pipeline.logs_url,
            run_number: pipeline.run_number,
            run_attempt: pipeline.run_attempt,
            total_jobs: pipeline.total_jobs,
            completed_jobs: pipeline.completed_jobs,
            failed_jobs: pipeline.failed_jobs,
            duration_seconds: pipeline.duration_seconds,
            started_at: pipeline.started_at&.iso8601,
            completed_at: pipeline.completed_at&.iso8601,
            created_at: pipeline.created_at.iso8601,
            updated_at: pipeline.updated_at.iso8601
          }
        end
      end
    end
  end
end

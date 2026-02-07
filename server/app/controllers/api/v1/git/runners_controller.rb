# frozen_string_literal: true

module Api
  module V1
    module Git
      class RunnersController < ApplicationController
        before_action :set_runner, only: %i[show destroy registration_token removal_token update_labels]
        before_action :validate_permissions

        # GET /api/v1/git/runners
        def index
          runners = ::Devops::GitRunner.where(account: current_user.account)

          # Filters
          runners = runners.where(status: params[:status]) if params[:status].present?
          runners = runners.by_scope(params[:scope]) if params[:scope].present?
          runners = runners.for_credential(params[:credential_id]) if params[:credential_id].present?
          runners = runners.for_repository(params[:repository_id]) if params[:repository_id].present?

          # Search by name
          runners = runners.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%") if params[:search].present?

          # Sorting
          case params[:sort]
          when "name"
            runners = runners.order(name: params[:direction] == "desc" ? :desc : :asc)
          when "status"
            runners = runners.order(status: params[:direction] == "desc" ? :desc : :asc)
          when "last_seen"
            runners = runners.order(last_seen_at: params[:direction] == "desc" ? :desc : :asc)
          else
            runners = runners.order(created_at: :desc)
          end

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          total_count = runners.count
          runners = runners.offset((page - 1) * per_page).limit(per_page)

          # Stats
          all_runners = ::Devops::GitRunner.where(account: current_user.account)
          stats = {
            total: all_runners.count,
            online: all_runners.online.count,
            offline: all_runners.offline.count,
            busy: all_runners.busy.count
          }

          render_success({
            runners: runners.map { |r| serialize_runner(r) },
            stats: stats,
            pagination: {
              current_page: page,
              per_page: per_page,
              total_count: total_count,
              total_pages: (total_count.to_f / per_page).ceil
            }
          })
        end

        # GET /api/v1/git/runners/:id
        def show
          render_success({ runner: serialize_runner_detail(@runner) })
        end

        # DELETE /api/v1/git/runners/:id
        def destroy
          credential = @runner.git_provider_credential
          return render_error("Credential not found", status: :unprocessable_content) unless credential&.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)

          # Delete from provider
          result = if @runner.repository_runner? && @runner.git_repository.present?
                     repo = @runner.git_repository
                     client.delete_runner(repo.owner, repo.name, @runner.external_id)
          elsif client.respond_to?(:delete_runner)
                     # Gitea uses a different signature
                     client.delete_runner(@runner.external_id)
          else
                     { success: false, error: "Delete not supported for this provider" }
          end

          if result[:success] != false
            @runner.destroy
            render_success(message: "Runner deleted successfully")
          else
            render_error(result[:error] || "Failed to delete runner", status: :unprocessable_content)
          end
        end

        # POST /api/v1/git/runners/sync
        def sync
          credential_id = params[:credential_id]
          repository_id = params[:repository_id]

          if credential_id.present?
            credential = current_user.account.git_provider_credentials.find(credential_id)
            synced = sync_runners_for_credential(credential, repository_id)
          else
            synced = 0
            current_user.account.git_provider_credentials.active.each do |cred|
              synced += sync_runners_for_credential(cred, repository_id)
            end
          end

          render_success({ synced_count: synced }, message: "Synced #{synced} runners")
        rescue ActiveRecord::RecordNotFound
          render_not_found("Credential")
        end

        # POST /api/v1/git/runners/:id/registration_token
        def registration_token
          credential = @runner.git_provider_credential
          return render_error("Credential not found", status: :unprocessable_content) unless credential&.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          result = get_registration_token(client, @runner)

          if result[:token].present?
            render_success({
              token: result[:token],
              expires_at: result[:expires_at]
            })
          else
            render_error(result[:error] || "Failed to get registration token", status: :unprocessable_content)
          end
        end

        # POST /api/v1/git/runners/:id/removal_token
        def removal_token
          credential = @runner.git_provider_credential
          return render_error("Credential not found", status: :unprocessable_content) unless credential&.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          result = get_removal_token(client, @runner)

          if result[:token].present?
            render_success({
              token: result[:token],
              expires_at: result[:expires_at]
            })
          else
            render_error(result[:error] || "Failed to get removal token", status: :unprocessable_content)
          end
        end

        # PUT /api/v1/git/runners/:id/labels
        def update_labels
          credential = @runner.git_provider_credential
          return render_error("Credential not found", status: :unprocessable_content) unless credential&.can_be_used?

          labels = params[:labels]
          return render_error("Labels parameter required", status: :unprocessable_content) unless labels.is_a?(Array)

          client = ::Devops::Git::ApiClient.for(credential)
          result = update_runner_labels_on_provider(client, @runner, labels)

          if result[:success] != false
            @runner.update!(labels: result[:labels] || labels)
            render_success({ runner: serialize_runner_detail(@runner) })
          else
            render_error(result[:error] || "Failed to update labels", status: :unprocessable_content)
          end
        end

        private

        def set_runner
          @runner = ::Devops::GitRunner.where(account: current_user.account).find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Runner")
        end

        def validate_permissions
          case action_name.to_sym
          when :index, :show
            return if current_user.has_permission?("git.runners.read")
          when :sync
            return if current_user.has_permission?("git.runners.read")
          when :destroy, :update_labels
            return if current_user.has_permission?("git.runners.manage")
          when :registration_token, :removal_token
            return if current_user.has_permission?("git.runners.token")
          end

          render_forbidden
        end

        def sync_runners_for_credential(credential, repository_id = nil)
          return 0 unless credential.can_be_used?

          client = ::Devops::Git::ApiClient.for(credential)
          synced = 0

          if repository_id.present?
            repository = credential.repositories.find(repository_id)
            synced += sync_repository_runners(client, credential, repository)
          else
            # Sync admin-level runners for Gitea (instance-wide runners)
            if client.is_a?(::Devops::Git::GiteaApiClient)
              synced += sync_admin_runners(client, credential)
            end

            # Sync all repository runners
            credential.repositories.each do |repo|
              synced += sync_repository_runners(client, credential, repo)
            end
          end

          synced
        rescue StandardError => e
          Rails.logger.error "Failed to sync runners for credential #{credential.id}: #{e.message}"
          0
        end

        def sync_admin_runners(client, credential)
          synced = 0

          begin
            runners_data = client.list_runners(:admin)
            return 0 unless runners_data.is_a?(Array)

            runners_data.each do |runner_data|
              ::Devops::GitRunner.sync_from_provider(
                credential,
                runner_data.stringify_keys,
                scope: "enterprise",
                repository: nil
              )
              synced += 1
            end
          rescue StandardError => e
            Rails.logger.warn "Admin runner sync not available for credential #{credential.id}: #{e.message}"
          end

          synced
        end

        def sync_repository_runners(client, credential, repository)
          synced = 0

          result = if client.respond_to?(:list_runners)
                     if client.is_a?(::Devops::Git::GiteaApiClient)
                       client.list_runners(:repo, repository.owner, repository.name)
                     else
                       client.list_runners(repository.owner, repository.name)
                     end
          end

          runners_data = result.is_a?(Hash) ? result[:runners] : result
          return 0 unless runners_data.is_a?(Array)

          runners_data.each do |runner_data|
            ::Devops::GitRunner.sync_from_provider(
              credential,
              runner_data.stringify_keys,
              scope: "repository",
              repository: repository
            )
            synced += 1
          end

          synced
        rescue StandardError => e
          Rails.logger.error "Failed to sync runners for repository #{repository.id}: #{e.message}"
          0
        end

        def get_registration_token(client, runner)
          if runner.repository_runner? && runner.git_repository.present?
            repo = runner.git_repository
            if client.is_a?(::Devops::Git::GiteaApiClient)
              client.runner_registration_token(:repo, repo.owner, repo.name)
            else
              client.runner_registration_token(repo.owner, repo.name)
            end
          elsif client.is_a?(::Devops::Git::GiteaApiClient)
            client.runner_registration_token(:admin)
          else
            { success: false, error: "Registration token not supported for this scope" }
          end
        end

        def get_removal_token(client, runner)
          if runner.repository_runner? && runner.git_repository.present?
            repo = runner.git_repository
            if client.respond_to?(:runner_removal_token)
              if client.is_a?(::Devops::Git::GiteaApiClient)
                client.runner_removal_token(:repo, repo.owner, repo.name)
              else
                client.runner_removal_token(repo.owner, repo.name)
              end
            else
              { success: false, error: "Removal token not supported" }
            end
          elsif client.is_a?(::Devops::Git::GiteaApiClient)
            client.runner_removal_token(:admin)
          else
            { success: false, error: "Removal token not supported for this scope" }
          end
        end

        def update_runner_labels_on_provider(client, runner, labels)
          if runner.repository_runner? && runner.git_repository.present?
            repo = runner.git_repository
            if client.respond_to?(:set_runner_labels)
              client.set_runner_labels(repo.owner, repo.name, runner.external_id, labels)
            elsif client.respond_to?(:update_runner_labels)
              client.update_runner_labels(runner.external_id, labels)
            else
              { success: false, error: "Label management not supported" }
            end
          elsif client.respond_to?(:update_runner_labels)
            client.update_runner_labels(runner.external_id, labels)
          else
            { success: false, error: "Label management not supported" }
          end
        end

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
            provider_type: runner.provider_type,
            repository_id: runner.git_repository_id,
            credential_id: runner.git_provider_credential_id
          }
        end

        def serialize_runner_detail(runner)
          serialize_runner(runner).merge(
            successful_jobs: runner.successful_jobs,
            failed_jobs: runner.failed_jobs,
            failure_rate: runner.failure_rate,
            recently_active: runner.recently_active?,
            repository: runner.git_repository ? {
              id: runner.git_repository.id,
              name: runner.git_repository.name,
              full_name: runner.git_repository.full_name
            } : nil,
            created_at: runner.created_at.iso8601,
            updated_at: runner.updated_at.iso8601
          )
        end
      end
    end
  end
end

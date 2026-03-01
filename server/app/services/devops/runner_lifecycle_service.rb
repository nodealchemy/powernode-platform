# frozen_string_literal: true

module Devops
  class RunnerLifecycleService
    def initialize(account:)
      @account = account
    end

    # Sync runners from one or all credentials
    def sync_runners(credential_id: nil, repository_id: nil)
      synced = 0

      if credential_id.present?
        credential = @account.git_provider_credentials.find(credential_id)
        synced = sync_credential_runners(credential, repository_id)
      else
        @account.git_provider_credentials.active.each do |cred|
          synced += sync_credential_runners(cred, repository_id)
        end
      end

      synced
    end

    # Delete a runner from provider and local DB
    def delete_runner(runner)
      credential = runner.git_provider_credential
      return { success: false, error: "Credential not found" } unless credential&.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return { success: false, error: "Provider does not support runners" } unless client.supports_runners?

      owner, repo = resolve_owner_repo(runner)
      scope = runner_scope_to_api_scope(runner)

      result = client.delete_runner(owner, repo, runner.external_id, scope: scope)

      if result[:success] != false
        runner.destroy
        { success: true }
      else
        { success: false, error: result[:error] || "Failed to delete runner" }
      end
    end

    # Get registration token for a runner's scope
    def registration_token(runner)
      credential = runner.git_provider_credential
      return { success: false, error: "Credential not found" } unless credential&.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return { success: false, error: "Provider does not support runners" } unless client.supports_runners?

      owner, repo = resolve_owner_repo(runner)
      scope = runner_scope_to_api_scope(runner)

      client.runner_registration_token(owner, repo, scope: scope)
    end

    # Get removal token for a runner's scope
    def removal_token(runner)
      credential = runner.git_provider_credential
      return { success: false, error: "Credential not found" } unless credential&.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return { success: false, error: "Provider does not support runners" } unless client.supports_runners?

      owner, repo = resolve_owner_repo(runner)
      scope = runner_scope_to_api_scope(runner)

      client.runner_removal_token(owner, repo, scope: scope)
    end

    # Update labels on provider and locally
    def update_labels(runner, labels)
      credential = runner.git_provider_credential
      return { success: false, error: "Credential not found" } unless credential&.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return { success: false, error: "Provider does not support runners" } unless client.supports_runners?

      owner, repo = resolve_owner_repo(runner)
      scope = runner_scope_to_api_scope(runner)

      result = client.set_runner_labels(owner, repo, runner.external_id, labels, scope: scope)

      if result[:success] != false
        runner.update!(labels: result[:labels] || labels)
        { success: true, labels: runner.labels }
      else
        { success: false, error: result[:error] || "Failed to update labels" }
      end
    end

    private

    def sync_credential_runners(credential, repository_id = nil)
      return 0 unless credential.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return 0 unless client.supports_runners?

      synced = 0

      if repository_id.present?
        repository = credential.repositories.find(repository_id)
        synced += sync_scope_runners(client, credential, :repo, repository.owner, repository.name, repository: repository)
      else
        # Sync admin-level runners (instance-wide)
        synced += sync_scope_runners(client, credential, :admin, nil, nil, scope_name: "enterprise")

        # Sync all repository runners
        credential.repositories.each do |repo|
          synced += sync_scope_runners(client, credential, :repo, repo.owner, repo.name, repository: repo)
        end
      end

      synced
    rescue StandardError => e
      Rails.logger.error "Failed to sync runners for credential #{credential.id}: #{e.message}"
      0
    end

    def sync_scope_runners(client, credential, api_scope, owner, repo, repository: nil, scope_name: nil)
      synced = 0
      scope_name ||= api_scope == :repo ? "repository" : api_scope.to_s

      result = client.list_runners(owner, repo, scope: api_scope)
      runners_data = extract_runners_list(result)
      return 0 unless runners_data.is_a?(Array)

      runners_data.each do |runner_data|
        ::Devops::GitRunner.sync_from_provider(
          credential,
          runner_data.is_a?(Hash) ? runner_data.stringify_keys : runner_data,
          scope: scope_name,
          repository: repository
        )
        synced += 1
      end

      synced
    rescue StandardError => e
      Rails.logger.warn "Runner sync not available for scope #{api_scope}: #{e.message}"
      0
    end

    # GitHub wraps runners in {runners:}, Gitea/GitLab return array
    def extract_runners_list(result)
      case result
      when Hash then result[:runners] || result["runners"] || []
      when Array then result
      else []
      end
    end

    def runner_scope_to_api_scope(runner)
      case runner.runner_scope
      when "repository" then :repo
      when "organization" then :org
      when "enterprise" then :admin
      else :repo
      end
    end

    def resolve_owner_repo(runner)
      if runner.repository_runner? && runner.git_repository.present?
        [runner.git_repository.owner, runner.git_repository.name]
      else
        [nil, nil]
      end
    end
  end
end

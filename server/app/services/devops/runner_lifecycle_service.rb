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

    # Mint a runner registration token for a scope WITHOUT a persisted GitRunner row.
    # Used to register ephemeral fleet builders before any GitRunner exists.
    # scope: :repo | :org | :admin. owner/repo required for :repo; owner required for :org.
    def registration_token_for_scope(credential:, scope: :repo, owner: nil, repo: nil)
      return { success: false, error: "Credential not found" } unless credential&.can_be_used?

      client = ::Devops::Git::ApiClient.for(credential)
      return { success: false, error: "Provider does not support runners" } unless client.supports_runners?

      scope = scope.to_sym
      case scope
      when :repo
        return { success: false, error: "owner and repo required for repo scope" } if owner.blank? || repo.blank?
      when :org
        return { success: false, error: "owner required for org scope" } if owner.blank?
      when :admin
        # no owner/repo needed
      else
        return { success: false, error: "Invalid scope: #{scope}" }
      end

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

      seen_external_ids = []

      runners_data.each do |runner_data|
        data = runner_data.is_a?(Hash) ? runner_data.stringify_keys : runner_data
        ::Devops::GitRunner.sync_from_provider(
          credential,
          data,
          scope: scope_name,
          repository: repository
        )
        seen_external_ids << data["id"].to_s if data.is_a?(Hash)
        synced += 1
      end

      prune_absent_runners(credential, scope_name, repository, seen_external_ids)

      synced
    rescue StandardError => e
      Rails.logger.warn "Runner sync not available for scope #{api_scope}: #{e.message}"
      0
    end

    # The sync was upsert-only, so a row whose upstream runner had vanished
    # survived forever. Fleet builders register EPHEMERAL and the provider drops
    # each after one job, so every sync that caught one mid-life left a
    # permanent "offline" phantom — 51 local rows against 4 upstream by
    # 2026-08-07, which makes the runner view useless for spotting a genuinely
    # offline runner, the one thing it exists for.
    #
    # The provider's listing is authoritative FOR THE SCOPE IT DESCRIBES, so a
    # row that scope no longer returns has no upstream counterpart. Two things
    # bound the delete:
    #
    #   1. REFUSE TO PRUNE ON AN EMPTY LISTING. extract_runners_list degrades
    #      every unexpected response shape to [] — an auth failure, a changed
    #      envelope, a partial outage — so pruning on empty would wipe an entire
    #      scope on a transient hiccup. That is far worse than the phantoms this
    #      removes. The cost is that a scope whose runners have all genuinely
    #      disappeared never self-cleans; that is the right trade and it is why
    #      this is not simply `where.not(id: seen)`.
    #   2. SCOPE THE DELETE EXACTLY to the credential + runner_scope +
    #      repository just listed. Absence from one scope's listing says nothing
    #      about any other scope, and a nil repository correctly narrows to
    #      git_repository_id IS NULL rather than matching every repo's rows.
    #
    # Note this deliberately does NOT consult System::CiRunnerLease the way the
    # operator's backlog-clearing script does: that model lives in the system
    # extension and core must never depend on an extension. It is not needed
    # here anyway — the lease guard exists to protect a builder mid-job, but a
    # runner absent from the authoritative listing is already gone upstream, so
    # the row is stale regardless of what a lease still believes.
    def prune_absent_runners(credential, scope_name, repository, seen_external_ids)
      return 0 if seen_external_ids.empty?

      stale = ::Devops::GitRunner.where(
        git_provider_credential_id: credential.id,
        runner_scope: scope_name,
        git_repository_id: repository&.id
      ).where.not(external_id: seen_external_ids)

      count = stale.count
      return 0 if count.zero?

      Rails.logger.info(
        "[RunnerLifecycleService] pruning #{count} #{scope_name} runner row(s) for credential " \
        "#{credential.id} with no upstream counterpart"
      )
      stale.delete_all
      count
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

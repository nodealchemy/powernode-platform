# frozen_string_literal: true

module Ai
  module Git
    class AgentWorkspaceService
      class WorkspaceError < StandardError; end
      class CredentialNotFoundError < WorkspaceError; end

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Provision a Git workspace for an agent
      # Creates or links a Devops::GitRepository for the agent
      #
      # @param agent [Ai::Agent] the agent needing a workspace
      # @param repository [Devops::GitRepository, nil] existing repository to use
      # @param backend [Symbol] git provider backend (:gitea, :github, :gitlab)
      # @return [Devops::GitRepository] the provisioned repository
      def provision_workspace(agent:, repository: nil, backend: :gitea)
        if repository
          Rails.logger.info("[AgentWorkspace] Linking existing repository #{repository.id} for agent #{agent.id}")
          return repository
        end

        credential = find_credential(backend: backend)
        raise CredentialNotFoundError, "No active #{backend} credential found" unless credential

        client = api_client_for(credential)
        repo_name = "agent-#{agent.slug}-workspace"

        # Create repository on the provider
        repo_data = client.create_repository(
          name: repo_name,
          description: "Workspace for agent: #{agent.name}",
          private: true
        )

        # Sync it into our database
        result = Devops::Git::ProviderManagementService.sync_single_repository(credential, repo_data)

        unless result[:success]
          raise WorkspaceError, "Failed to sync repository: #{result[:error]}"
        end

        Rails.logger.info("[AgentWorkspace] Provisioned workspace #{result[:repository].id} for agent #{agent.id}")
        result[:repository]
      rescue StandardError => e
        Rails.logger.error("[AgentWorkspace] Failed to provision workspace for agent #{agent.id}: #{e.message}")
        raise
      end

      # Configure webhooks on a repository
      #
      # @param repository [Devops::GitRepository] the repository to configure
      # @param events [Array<Symbol>] webhook events to subscribe to
      # @return [Hash] result of webhook configuration
      def setup_webhooks(repository:, events: [:push, :pull_request])
        Devops::Git::ProviderManagementService.configure_webhook(repository, events)
      end

      # Create a worktree for agent work within a repository
      #
      # @param repository [Devops::GitRepository] the repository
      # @param session [Object] the worktree session (provides id and branch info)
      # @return [Hash] worktree creation result
      def clone_to_worktree(repository:, session:)
        manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)
        manager.create_worktree(
          session_id: session.id,
          branch_suffix: "agent-work",
          base_branch: repository.default_branch || "main"
        )
      end

      # Clean up all workspaces for an agent
      #
      # @param agent [Ai::Agent] the agent whose workspaces to clean up
      # @return [Integer] number of workspaces cleaned up
      def cleanup_workspace(agent:)
        repositories = Devops::GitRepository.where(account: account)
                                            .where("name LIKE ?", "agent-#{agent.slug}-%")
        count = 0

        repositories.find_each do |repo|
          repo.destroy
          count += 1
        end

        Rails.logger.info("[AgentWorkspace] Cleaned up #{count} workspace(s) for agent #{agent.id}")
        count
      end

      private

      def find_credential(backend:)
        account.git_provider_credentials
               .joins(:provider)
               .where(git_providers: { provider_type: backend.to_s })
               .active
               .order(is_default: :desc, created_at: :desc)
               .first
      end

      def management_service(credential)
        Devops::Git::ProviderManagementService
      end

      def api_client_for(credential)
        Devops::Git::ApiClient.for(credential)
      end
    end
  end
end

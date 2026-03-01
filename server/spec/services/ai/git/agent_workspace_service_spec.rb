# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Git::AgentWorkspaceService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account) }

  describe '#provision_workspace' do
    context 'when an existing repository is provided' do
      let(:repository) { double('repository', id: SecureRandom.uuid) }

      it 'returns the existing repository' do
        result = service.provision_workspace(agent: agent, repository: repository)
        expect(result).to eq(repository)
      end
    end

    context 'when no repository is provided' do
      let(:credential) { double('credential', id: SecureRandom.uuid) }
      let(:client) { double('api_client') }
      let(:repo_data) { { "name" => "agent-#{agent.slug}-workspace" } }
      let(:synced_repo) { double('git_repository', id: SecureRandom.uuid) }

      before do
        # Stub credential lookup
        provider_rel = double('provider_relation')
        cred_rel = double('cred_relation')
        active_rel = double('active_relation')
        ordered_rel = double('ordered_relation')

        allow(account).to receive(:git_provider_credentials).and_return(provider_rel)
        allow(provider_rel).to receive(:joins).with(:provider).and_return(cred_rel)
        allow(cred_rel).to receive(:where).and_return(active_rel)
        allow(active_rel).to receive(:active).and_return(ordered_rel)
        allow(ordered_rel).to receive(:order).and_return(ordered_rel)
        allow(ordered_rel).to receive(:first).and_return(credential)

        allow(Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client)
        allow(client).to receive(:create_repository).and_return(repo_data)
      end

      it 'creates a repository and syncs it' do
        allow(Devops::Git::ProviderManagementService).to receive(:sync_single_repository)
          .and_return({ success: true, repository: synced_repo })

        result = service.provision_workspace(agent: agent)
        expect(result).to eq(synced_repo)
      end

      it 'raises WorkspaceError when sync fails' do
        allow(Devops::Git::ProviderManagementService).to receive(:sync_single_repository)
          .and_return({ success: false, error: "Sync failed" })

        expect {
          service.provision_workspace(agent: agent)
        }.to raise_error(Ai::Git::AgentWorkspaceService::WorkspaceError, /Failed to sync/)
      end

      it 'raises CredentialNotFoundError when no credential exists' do
        allow(account).to receive(:git_provider_credentials).and_return(double('rel').tap { |r|
          allow(r).to receive(:joins).and_return(r)
          allow(r).to receive(:where).and_return(r)
          allow(r).to receive(:active).and_return(r)
          allow(r).to receive(:order).and_return(r)
          allow(r).to receive(:first).and_return(nil)
        })

        expect {
          service.provision_workspace(agent: agent)
        }.to raise_error(Ai::Git::AgentWorkspaceService::CredentialNotFoundError)
      end
    end
  end

  describe '#setup_webhooks' do
    let(:repository) { double('repository') }

    it 'delegates to ProviderManagementService' do
      expected_result = { success: true }
      allow(Devops::Git::ProviderManagementService).to receive(:configure_webhook)
        .with(repository, [:push, :pull_request]).and_return(expected_result)

      result = service.setup_webhooks(repository: repository)
      expect(result).to eq(expected_result)
    end

    it 'accepts custom events' do
      allow(Devops::Git::ProviderManagementService).to receive(:configure_webhook)
        .with(repository, [:push]).and_return({ success: true })

      result = service.setup_webhooks(repository: repository, events: [:push])
      expect(result).to eq({ success: true })
    end
  end

  describe '#clone_to_worktree' do
    let(:repository) { double('repository', default_branch: "main") }
    let(:session) { double('session', id: SecureRandom.uuid, repository_path: "/tmp/repo") }
    let(:manager) { instance_double(Ai::Git::WorktreeManager) }

    before do
      allow(Ai::Git::WorktreeManager).to receive(:new).with(repository_path: "/tmp/repo").and_return(manager)
    end

    it 'creates a worktree via WorktreeManager' do
      expected_result = { path: "/tmp/worktree", branch: "agent-work-abc" }
      allow(manager).to receive(:create_worktree).and_return(expected_result)

      result = service.clone_to_worktree(repository: repository, session: session)
      expect(result).to eq(expected_result)
      expect(manager).to have_received(:create_worktree).with(
        session_id: session.id,
        branch_suffix: "agent-work",
        base_branch: "main"
      )
    end

    it 'uses default_branch from repository' do
      allow(repository).to receive(:default_branch).and_return("develop")
      allow(manager).to receive(:create_worktree).and_return({})

      service.clone_to_worktree(repository: repository, session: session)
      expect(manager).to have_received(:create_worktree).with(
        hash_including(base_branch: "develop")
      )
    end
  end

  describe '#cleanup_workspace' do
    it 'destroys matching repositories and returns count' do
      # Stub the repository query
      repo1 = double('repo1', destroy: true)
      repo2 = double('repo2', destroy: true)
      relation = double('relation')
      allow(Devops::GitRepository).to receive(:where).with(account: account).and_return(relation)
      allow(relation).to receive(:where).and_return(relation)
      allow(relation).to receive(:find_each).and_yield(repo1).and_yield(repo2)

      result = service.cleanup_workspace(agent: agent)
      expect(result).to eq(2)
    end

    it 'returns 0 when no matching repositories exist' do
      relation = double('relation')
      allow(Devops::GitRepository).to receive(:where).with(account: account).and_return(relation)
      allow(relation).to receive(:where).and_return(relation)
      allow(relation).to receive(:find_each)

      result = service.cleanup_workspace(agent: agent)
      expect(result).to eq(0)
    end
  end
end

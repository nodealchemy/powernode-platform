# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ProjectInitializationService, type: :service do
  let(:account) { create(:account) }

  describe '#initialize' do
    it 'sets defaults' do
      service = described_class.new(account: account)

      expect(service.account).to eq(account)
      expect(service.repo_name).to eq('todo-app')
      expect(service.description).to include('Full-stack Todo/Task application')
    end

    it 'accepts custom repo_name and description' do
      service = described_class.new(account: account, repo_name: 'my-app', description: 'Custom app')

      expect(service.repo_name).to eq('my-app')
      expect(service.description).to eq('Custom app')
    end
  end

  describe '#call' do
    subject(:service) { described_class.new(account: mock_account, repo_name: 'test-repo') }

    let(:git_provider) { instance_double(Devops::GitProvider, id: SecureRandom.uuid) }
    let(:credential) do
      instance_double(
        Devops::GitProviderCredential,
        credentials: { 'username' => 'testuser' },
        name: 'testuser'
      )
    end
    let(:client) { double("ApiClient") }

    # Use a double for account since the service calls git_providers which
    # is not defined on the Account model (likely an enterprise association)
    let(:mock_account) do
      double("Account",
        id: account.id,
        git_providers: git_providers_relation,
        git_provider_credentials: cred_relation
      )
    end

    let(:git_providers_relation) { double("git_providers") }
    let(:cred_relation) { double("credentials") }

    context 'when no gitea credential is found' do
      before do
        allow(git_providers_relation).to receive(:find_by).with(provider_type: 'gitea').and_return(nil)
        allow(Devops::GitProvider).to receive(:find_by).with(provider_type: 'gitea').and_return(nil)
      end

      it 'returns an error result' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('No active Gitea credential found')
      end
    end

    context 'when gitea credential is found via account git_providers' do
      before do
        allow(git_providers_relation).to receive(:find_by).with(provider_type: 'gitea').and_return(git_provider)

        allow(cred_relation).to receive(:where).and_return(cred_relation)
        allow(cred_relation).to receive(:order).and_return(cred_relation)
        allow(cred_relation).to receive(:first).and_return(credential)

        allow(Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client)
      end

      context 'when repository creation succeeds' do
        before do
          allow(client).to receive(:create_repository).and_return({
            success: true,
            clone_url: 'https://gitea.example.com/testuser/test-repo.git'
          })
          allow(client).to receive(:create_file).and_return({ success: true })
        end

        it 'returns success with repository info' do
          result = service.call

          expect(result[:success]).to be true
          expect(result[:repository][:name]).to eq('test-repo')
          expect(result[:repository][:default_branch]).to eq('master')
        end

        it 'creates initial files in the repository' do
          result = service.call

          expect(result[:files_created]).to include('README.md', '.gitignore', 'docs/ARCHITECTURE.md', 'docs/TASKS.md')
        end

        it 'calls create_file for each initial file' do
          service.call

          expect(client).to have_received(:create_file).exactly(4).times
        end
      end

      context 'when repository creation fails' do
        before do
          allow(client).to receive(:create_repository).and_return({
            success: false,
            error: 'Repository already exists'
          })
        end

        it 'returns the error result from client' do
          result = service.call

          expect(result[:success]).to be false
        end
      end

      context 'when some file creations fail' do
        before do
          allow(client).to receive(:create_repository).and_return({
            success: true,
            clone_url: 'https://gitea.example.com/testuser/test-repo.git'
          })

          call_count = 0
          allow(client).to receive(:create_file) do
            call_count += 1
            if call_count == 2
              { success: false, error: 'file exists' }
            else
              { success: true }
            end
          end
        end

        it 'includes only successfully created files' do
          result = service.call

          expect(result[:files_created].size).to eq(3)
        end
      end
    end

    context 'when gitea credential is found via global provider' do
      let(:global_git_provider) { instance_double(Devops::GitProvider, id: SecureRandom.uuid) }

      before do
        allow(git_providers_relation).to receive(:find_by).with(provider_type: 'gitea').and_return(nil)
        allow(Devops::GitProvider).to receive(:find_by).with(provider_type: 'gitea').and_return(global_git_provider)

        allow(cred_relation).to receive(:where).and_return(cred_relation)
        allow(cred_relation).to receive(:order).and_return(cred_relation)
        allow(cred_relation).to receive(:first).and_return(credential)

        allow(Devops::Git::ApiClient).to receive(:for).with(credential).and_return(client)
        allow(client).to receive(:create_repository).and_return({
          success: true,
          clone_url: 'https://gitea.example.com/testuser/test-repo.git'
        })
        allow(client).to receive(:create_file).and_return({ success: true })
      end

      it 'falls back to global provider and succeeds' do
        result = service.call

        expect(result[:success]).to be true
      end
    end
  end
end

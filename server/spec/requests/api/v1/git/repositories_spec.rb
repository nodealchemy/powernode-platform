# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::Repositories', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'git.repositories.read', 'git.repositories.delete', 'git.repositories.sync', 'git.repositories.webhooks.manage', 'git.pipelines.read' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'git.repositories.read' ]) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/git/repositories' do
    let!(:repo1) { create(:devops_git_repository, account: account, name: 'repo1') }
    let!(:repo2) { create(:devops_git_repository, account: account, name: 'repo2') }
    let!(:other_repo) { create(:devops_git_repository, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of repositories for current account' do
        get '/api/v1/git/repositories', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['repositories']).to be_an(Array)
        expect(data['repositories'].length).to eq(2)
        expect(data['repositories'].none? { |r| r['id'] == other_repo.id }).to be true
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by search term' do
        get '/api/v1/git/repositories', params: { search: 'repo1' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['repositories'].length).to eq(1)
        expect(data['repositories'].first['name']).to eq('repo1')
      end

      it 'filters by visibility' do
        private_repo = create(:devops_git_repository, account: account, is_private: true)

        get '/api/v1/git/repositories', params: { visibility: 'private' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['repositories'].all? { |r| r['is_private'] }).to be true
      end

      it 'supports pagination' do
        # Controller enforces minimum per_page of 20, so create enough repos for pagination to matter
        get '/api/v1/git/repositories', params: { page: 1, per_page: 20 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['repositories'].length).to be <= 20
        expect(data['pagination']['per_page']).to eq(20)
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/repositories', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/repositories', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:other_repository) { create(:devops_git_repository, account: other_account) }

    context 'with proper permissions' do
      it 'returns repository details' do
        get "/api/v1/git/repositories/#{repository.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['repository']).to include(
          'id' => repository.id,
          'name' => repository.name,
          'full_name' => repository.full_name
        )
      end

      it 'returns not found for non-existent repository' do
        get "/api/v1/git/repositories/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing repository from different account' do
      it 'returns not found error' do
        get "/api/v1/git/repositories/#{other_repository.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/git/repositories/:id' do
    let!(:repository) { create(:devops_git_repository, account: account) }

    context 'with proper permissions' do
      it 'deletes the repository' do
        expect {
          delete "/api/v1/git/repositories/#{repository.id}", headers: headers, as: :json
        }.to change { account.git_repositories.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Repository removed successfully')
      end
    end

    context 'without git.repositories.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/git/repositories/#{repository.id}", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/repositories/sync' do
    let(:credential) { create(:devops_git_provider_credential, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(WorkerApiClient).to receive(:queue_git_repository_sync)
      end

      it 'queues repository sync job' do
        post '/api/v1/git/repositories/sync',
             params: { credential_id: credential.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:accepted)
        data = json_response_data
        expect(data['message']).to eq('Repository sync has been queued')
      end

      it 'returns not found for non-existent credential' do
        post '/api/v1/git/repositories/sync',
             params: { credential_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Credential not found')
      end
    end

    context 'without git.repositories.sync permission' do
      it 'returns forbidden error' do
        post '/api/v1/git/repositories/sync',
             params: { credential_id: credential.id },
             headers: read_only_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/repositories/:id/configure_webhook' do
    let(:repository) { create(:devops_git_repository, account: account, webhook_configured: false) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitRepository).to receive(:configure_webhook!).and_return({ success: true })
      end

      it 'configures webhook for repository' do
        post "/api/v1/git/repositories/#{repository.id}/configure_webhook", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Webhook configured successfully')
      end

      it 'returns error on failure' do
        allow_any_instance_of(Devops::GitRepository).to receive(:configure_webhook!).and_return({ success: false, error: 'API error' })

        post "/api/v1/git/repositories/#{repository.id}/configure_webhook", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('API error')
      end
    end

    context 'without git.repositories.webhooks.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/repositories/#{repository.id}/configure_webhook", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/git/repositories/:id/remove_webhook' do
    let(:repository) { create(:devops_git_repository, account: account, webhook_configured: true) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitRepository).to receive(:remove_webhook!).and_return({ success: true })
      end

      it 'removes webhook from repository' do
        delete "/api/v1/git/repositories/#{repository.id}/remove_webhook", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Webhook removed successfully')
      end
    end

    context 'without git.repositories.webhooks.manage permission' do
      it 'returns forbidden error' do
        delete "/api/v1/git/repositories/#{repository.id}/remove_webhook", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id/branches' do
    let(:repository) { create(:devops_git_repository, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(list_branches: [ { name: 'main' }, { name: 'develop' } ]))
      end

      it 'returns list of branches' do
        get "/api/v1/git/repositories/#{repository.id}/branches", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['branches']).to be_an(Array)
        expect(data['branches'].length).to eq(2)
      end

      it 'returns error when credential cannot be used' do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(false)

        get "/api/v1/git/repositories/#{repository.id}/branches", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Credential cannot be used')
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/branches", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id/commits' do
    let(:repository) { create(:devops_git_repository, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(list_commits: [ { sha: 'abc123', message: 'Initial commit' } ]))
      end

      it 'returns list of commits' do
        get "/api/v1/git/repositories/#{repository.id}/commits", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['commits']).to be_an(Array)
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/commits", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id/pipelines' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let!(:pipeline1) { create(:devops_git_pipeline, repository: repository, account: account, status: 'completed', conclusion: 'success') }
    let!(:pipeline2) { create(:devops_git_pipeline, repository: repository, account: account, status: 'in_progress') }

    context 'with proper permissions' do
      it 'returns list of pipelines' do
        get "/api/v1/git/repositories/#{repository.id}/pipelines", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pipelines']).to be_an(Array)
        expect(data['pipelines'].length).to eq(2)
        expect(data['stats']).to include('total_runs', 'success_count', 'failed_count')
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        get "/api/v1/git/repositories/#{repository.id}/pipelines", params: { status: 'in_progress' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['pipelines'].all? { |p| p['status'] == 'in_progress' }).to be true
      end
    end

    context 'without git.pipelines.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/pipelines", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id/commits/:sha' do
    let(:repository) { create(:devops_git_repository, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(get_commit: { sha: 'abc123', message: 'Commit message' }))
      end

      it 'returns commit details' do
        get "/api/v1/git/repositories/#{repository.id}/commits/abc123", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['commit']).to include('sha' => 'abc123')
      end

      it 'returns not found for non-existent commit' do
        allow(Devops::Git::ApiClient).to receive(:for).and_return(
          double(get_commit: nil).tap { |d|
            allow(d).to receive(:get_commit).and_raise(Devops::Git::ApiClient::NotFoundError.new("Not found"))
          }
        )

        get "/api/v1/git/repositories/#{repository.id}/commits/nonexistent", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/commits/abc123", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/git/repositories/:id/contents/*path' do
    let(:repository) { create(:devops_git_repository, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(get_file_content: { content: 'file content', path: 'README.md' }))
      end

      it 'returns file content' do
        get "/api/v1/git/repositories/#{repository.id}/contents/README.md", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['content']).to be_present
      end
    end

    context 'without git.repositories.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/repositories/#{repository.id}/contents/README.md", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

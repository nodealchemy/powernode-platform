# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::Runners', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'git.runners.read', 'git.runners.manage', 'git.runners.token' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'git.runners.read' ]) }
  let(:no_permission_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:no_permission_headers) { auth_headers_for(no_permission_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/git/runners' do
    let!(:runner1) { create(:devops_git_runner, account: account, status: 'online') }
    let!(:runner2) { create(:devops_git_runner, account: account, status: 'offline') }
    let!(:other_runner) { create(:devops_git_runner, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of runners for current account' do
        get '/api/v1/git/runners', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['runners']).to be_an(Array)
        expect(data['runners'].length).to eq(2)
        expect(data['runners'].none? { |r| r['id'] == other_runner.id }).to be true
        expect(data['stats']).to include('total', 'online', 'offline', 'busy')
        expect(data['pagination']).to include('current_page', 'per_page', 'total_count', 'total_pages')
      end

      it 'filters by status' do
        get '/api/v1/git/runners', params: { status: 'online' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['runners'].length).to eq(1)
        expect(data['runners'].first['status']).to eq('online')
      end

      it 'searches by name' do
        runner3 = create(:devops_git_runner, account: account, name: 'special-runner')

        get '/api/v1/git/runners', params: { search: 'special' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['runners'].any? { |r| r['name'] == 'special-runner' }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/git/runners', params: { page: 1, per_page: 1 }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['runners'].length).to eq(1)
        expect(data['pagination']['per_page']).to eq(1)
      end

      it 'sorts by name' do
        get '/api/v1/git/runners', params: { sort: 'name', direction: 'asc' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['runners']).to be_an(Array)
      end
    end

    context 'without git.runners.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/git/runners', headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/runners', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/git/runners/:id' do
    let(:runner) { create(:devops_git_runner, account: account) }
    let(:other_runner) { create(:devops_git_runner, account: other_account) }

    context 'with proper permissions' do
      it 'returns runner details' do
        get "/api/v1/git/runners/#{runner.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['runner']).to include(
          'id' => runner.id,
          'name' => runner.name,
          'status' => runner.status
        )
      end

      it 'returns not found for non-existent runner' do
        get "/api/v1/git/runners/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'accessing runner from different account' do
      it 'returns not found error' do
        get "/api/v1/git/runners/#{other_runner.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.runners.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/git/runners/#{runner.id}", headers: no_permission_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/git/runners/:id' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let!(:runner) { create(:devops_git_runner, account: account, repository: repository, runner_scope: 'repository') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(supports_runners?: true, delete_runner: { success: true }))
      end

      it 'deletes the runner' do
        expect {
          delete "/api/v1/git/runners/#{runner.id}", headers: headers, as: :json
        }.to change { Devops::GitRunner.count }.by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Runner deleted successfully')
      end

      it 'returns error when credential cannot be used' do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(false)

        delete "/api/v1/git/runners/#{runner.id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Credential not found')
      end
    end

    context 'without git.runners.manage permission' do
      it 'returns forbidden error' do
        delete "/api/v1/git/runners/#{runner.id}", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/runners/sync' do
    let(:credential) { create(:devops_git_provider_credential, account: account) }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(supports_runners?: true, list_runners: []))
      end

      it 'syncs runners for credential' do
        post '/api/v1/git/runners/sync',
             params: { credential_id: credential.id },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['synced_count']).to be_a(Integer)
      end

      it 'syncs all credentials when no credential_id provided' do
        post '/api/v1/git/runners/sync', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['synced_count']).to be_a(Integer)
      end

      it 'returns not found for non-existent credential' do
        post '/api/v1/git/runners/sync',
             params: { credential_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without git.runners.read permission' do
      it 'returns forbidden error' do
        post '/api/v1/git/runners/sync',
             params: { credential_id: credential.id },
             headers: no_permission_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/runners/:id/registration_token' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:runner) { create(:devops_git_runner, account: account, repository: repository, runner_scope: 'repository') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(supports_runners?: true, runner_registration_token: { token: 'reg-token-123', expires_at: 1.hour.from_now }))
      end

      it 'returns registration token' do
        post "/api/v1/git/runners/#{runner.id}/registration_token", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['token']).to eq('reg-token-123')
        expect(data['expires_at']).to be_present
      end

      it 'returns error when credential cannot be used' do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(false)

        post "/api/v1/git/runners/#{runner.id}/registration_token", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Credential not found')
      end
    end

    context 'without git.runners.token permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/runners/#{runner.id}/registration_token", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/runners/:id/removal_token' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:runner) { create(:devops_git_runner, account: account, repository: repository, runner_scope: 'repository') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(supports_runners?: true, runner_removal_token: { token: 'rem-token-123', expires_at: 1.hour.from_now }))
      end

      it 'returns removal token' do
        post "/api/v1/git/runners/#{runner.id}/removal_token", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['token']).to eq('rem-token-123')
        expect(data['expires_at']).to be_present
      end
    end

    context 'without git.runners.token permission' do
      it 'returns forbidden error' do
        post "/api/v1/git/runners/#{runner.id}/removal_token", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/git/runners/:id/labels' do
    let(:repository) { create(:devops_git_repository, account: account) }
    let(:runner) { create(:devops_git_runner, account: account, repository: repository, runner_scope: 'repository') }

    context 'with proper permissions' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        allow(Devops::Git::ApiClient).to receive(:for).and_return(double(supports_runners?: true, set_runner_labels: { success: true, labels: [ 'label1', 'label2' ] }))
      end

      it 'updates runner labels' do
        put "/api/v1/git/runners/#{runner.id}/labels",
            params: { labels: [ 'label1', 'label2' ] },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['runner']).to be_present
      end

      it 'returns error when labels parameter is missing' do
        put "/api/v1/git/runners/#{runner.id}/labels", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Labels parameter required')
      end

      it 'returns error when labels is not an array' do
        put "/api/v1/git/runners/#{runner.id}/labels",
            params: { labels: 'not-an-array' },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('Labels parameter required')
      end
    end

    context 'without git.runners.manage permission' do
      it 'returns forbidden error' do
        put "/api/v1/git/runners/#{runner.id}/labels",
            params: { labels: [ 'label1' ] },
            headers: read_only_headers,
            as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end

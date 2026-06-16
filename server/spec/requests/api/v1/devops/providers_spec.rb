# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Providers', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'devops.providers.read' ]) }
  let(:user_with_write_permission) { create(:user, account: account, permissions: [ 'devops.providers.read', 'devops.providers.write' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/providers' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:git_provider, 3, account: account)
    end

    context 'with devops.providers.read permission' do
      it 'returns list of providers' do
        get '/api/v1/devops/providers', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['providers']).to be_an(Array)
        expect(response_data['data']['providers'].length).to eq(3)
      end

      it 'includes meta information' do
        get '/api/v1/devops/providers', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['meta']).to include('total', 'by_type')
      end

      it 'filters by provider_type' do
        create(:git_provider, account: account, provider_type: 'gitlab')

        get '/api/v1/devops/providers',
            params: { provider_type: 'gitlab' },
            headers: headers

        expect_success_response
        response_data = json_response

        types = response_data['data']['providers'].map { |p| p['provider_type'] }
        expect(types.uniq).to eq([ 'gitlab' ])
      end

      it 'filters by is_active' do
        create(:git_provider, account: account, is_active: false)

        get '/api/v1/devops/providers',
            params: { is_active: false },
            headers: headers

        expect_success_response
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/providers', headers: headers, as: :json

        expect_error_response('Insufficient permissions to view DevOps providers', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/providers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/providers/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with devops.providers.read permission' do
      it 'returns provider details' do
        get "/api/v1/devops/providers/#{provider.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['provider']).to include('id' => provider.id)
      end

      it 'includes repositories when requested' do
        # serialize_provider(include_repositories:) pulls repositories via the
        # provider's account credentials (git_provider_credential_id), so attach
        # the repos to a credential of this provider.
        credential = create(:git_provider_credential, provider: provider, account: account)
        create_list(:git_repository, 2, credential: credential, account: account)

        get "/api/v1/devops/providers/#{provider.id}",
            params: { include_repositories: true },
            headers: headers

        expect_success_response
        response_data = json_response

        expect(response_data['data']['provider']).to have_key('repositories')
      end
    end

    context 'when provider does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/providers/nonexistent-id', headers: headers, as: :json

        expect_error_response('Provider not found', 404)
      end
    end

    context 'when accessing other account provider' do
      let(:other_account) { create(:account) }
      let(:other_provider) { create(:git_provider, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/devops/providers/#{other_provider.id}", headers: headers, as: :json

        expect_error_response('Provider not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/providers' do
    let(:headers) { auth_headers_for(user_with_write_permission) }

    context 'with devops.providers.write permission' do
      let(:valid_params) do
        {
          provider: {
            name: 'Test Provider',
            provider_type: 'github',
            api_base_url: 'https://api.github.com',
            web_base_url: 'https://github.com',
            is_active: true,
            capabilities: %w[repos branches]
          }
        }
      end

      it 'creates a new provider' do
        # provider_params permits name/provider_type/api_base_url/web_base_url/
        # is_active/capabilities and the controller builds account.git_providers.
        expect {
          post '/api/v1/devops/providers', params: valid_params, headers: headers, as: :json
        }.to change(Devops::GitProvider, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response
        expect(response_data['data']['provider']['name']).to eq('Test Provider')
        expect(response_data['data']['provider']['provider_type']).to eq('github')
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          provider: {
            name: ''
          }
        }
      end

      it 'returns validation error' do
        post '/api/v1/devops/providers', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/providers',
             params: { provider: { name: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions to manage DevOps providers', 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/providers/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with devops.providers.write permission' do
      it 'updates provider successfully' do
        patch "/api/v1/devops/providers/#{provider.id}",
              params: { provider: { name: 'Updated Provider' } },
              headers: headers,
              as: :json

        expect_success_response

        provider.reload
        expect(provider.name).to eq('Updated Provider')
      end

      it 'updates is_active status' do
        patch "/api/v1/devops/providers/#{provider.id}",
              params: { provider: { is_active: false } },
              headers: headers,
              as: :json

        expect_success_response

        provider.reload
        expect(provider.is_active).to be false
      end
    end
  end

  describe 'DELETE /api/v1/devops/providers/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with devops.providers.write permission' do
      it 'deletes provider successfully' do
        provider_id = provider.id

        delete "/api/v1/devops/providers/#{provider_id}", headers: headers, as: :json

        expect_success_response
        expect(Devops::GitProvider.find_by(id: provider_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/devops/providers/:id/test_connection' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:git_provider, account: account) }
    # The controller resolves the account's default credential and tests it via
    # Devops::Git::ProviderTestService (NOT provider.test_connection), mirroring
    # the git/providers_controller_spec #test_credential pattern.
    let!(:credential) do
      create(:git_provider_credential, :default, provider: provider, account: account)
    end

    context 'with devops.providers.read permission' do
      it 'tests connection successfully' do
        allow_any_instance_of(::Devops::Git::ProviderTestService).to receive(:test_connection).and_return(
          { success: true, message: 'Connection successful' }
        )

        post "/api/v1/devops/providers/#{provider.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['connected']).to be true
      end

      it 'handles connection failures' do
        allow_any_instance_of(::Devops::Git::ProviderTestService).to receive(:test_connection).and_return(
          { success: false, error: 'Connection failed' }
        )

        post "/api/v1/devops/providers/#{provider.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['connected']).to be false
      end

      it 'returns an error when no credentials are configured' do
        # Unset the default flag so default_credential_for_account returns nil and
        # the controller's guard clause fires. (destroy! is blocked by the
        # prevent_destroy_if_default_and_only guard when it's the only credential.)
        credential.update_columns(is_default: false)

        post "/api/v1/devops/providers/#{provider.id}/test_connection", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to eq('No credentials configured for this provider')
      end
    end
  end

  describe 'POST /api/v1/devops/providers/:id/sync_repositories' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with devops.providers.write permission' do
      it 'initiates repository sync successfully' do
        allow(WorkerJobService).to receive(:enqueue_job).and_return(true)

        post "/api/v1/devops/providers/#{provider.id}/sync_repositories", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['job_queued']).to be true
      end

      it 'handles worker service unavailability' do
        allow(WorkerJobService).to receive(:enqueue_job).and_raise(
          WorkerJobService::WorkerServiceError.new('Worker unavailable')
        )

        post "/api/v1/devops/providers/#{provider.id}/sync_repositories", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['job_queued']).to be false
      end
    end
  end
end

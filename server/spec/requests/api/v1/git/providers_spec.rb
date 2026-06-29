# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::Providers', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'git.providers.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'git.providers.read', 'git.providers.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'git.providers.read', 'git.providers.update' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'git.providers.read', 'git.providers.delete' ]) }
  let(:user_with_credential_permissions) do
    create(:user, account: account, permissions: [
      'git.providers.read', 'git.credentials.read', 'git.credentials.create',
      'git.credentials.update', 'git.credentials.delete', 'git.credentials.test',
      'git.repositories.read', 'git.repositories.sync'
    ])
  end
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/git/providers' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:git_provider, 3, account: account)
    end

    context 'with git.providers.read permission' do
      it 'returns list of providers' do
        get '/api/v1/git/providers', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['providers']).to be_an(Array)
        expect(response_data['data']['providers'].length).to eq(3)
      end

      it 'does not return another account\'s providers (cross-tenant isolation)' do
        other = create(:account)
        create(:git_provider, account: other, name: 'Foreign Provider')

        get '/api/v1/git/providers', headers: headers, as: :json

        names = json_response['data']['providers'].map { |p| p['name'] }
        expect(names).not_to include('Foreign Provider')
        expect(json_response['data']['providers'].length).to eq(3)
      end

      it 'includes provider details' do
        get '/api/v1/git/providers', headers: headers, as: :json

        response_data = json_response
        first_provider = response_data['data']['providers'].first

        expect(first_provider).to include('id', 'name', 'provider_type', 'is_active')
      end

      it 'includes pagination' do
        get '/api/v1/git/providers', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by provider_type' do
        create(:git_provider, :github, account: account)

        get '/api/v1/git/providers',
            params: { provider_type: 'github' },
            headers: headers

        expect_success_response
        response_data = json_response

        provider_types = response_data['data']['providers'].map { |p| p['provider_type'] }
        expect(provider_types.uniq).to eq([ 'github' ])
      end

      it 'searches by name' do
        create(:git_provider, name: 'Unique Search Provider', account: account)

        get '/api/v1/git/providers',
            params: { search: 'Unique Search' },
            headers: headers

        expect_success_response
        response_data = json_response

        expect(response_data['data']['providers'].length).to eq(1)
        expect(response_data['data']['providers'].first['name']).to include('Unique Search')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/git/providers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/providers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/git/providers/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:provider) { create(:git_provider, :github, account: account) }

    context 'with git.providers.read permission' do
      it 'returns provider details' do
        get "/api/v1/git/providers/#{provider.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['provider']).to include(
          'id' => provider.id,
          'name' => provider.name,
          'provider_type' => provider.provider_type
        )
      end

      it 'includes capabilities' do
        get "/api/v1/git/providers/#{provider.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['provider']).to have_key('capabilities')
      end

      it 'includes oauth config without secrets' do
        get "/api/v1/git/providers/#{provider.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['provider']).to have_key('oauth_config')
      end
    end

    context 'when provider does not exist' do
      it 'returns not found error' do
        get '/api/v1/git/providers/nonexistent-id', headers: headers, as: :json

        expect_error_response('Provider not found', 404)
      end
    end
  end

  describe 'POST /api/v1/git/providers' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with git.providers.create permission' do
      let(:valid_params) do
        {
          provider: {
            name: 'New Git Provider',
            slug: 'new-git-provider',
            provider_type: 'github',
            api_base_url: 'https://api.github.com',
            capabilities: [ 'repos', 'branches' ]
          }
        }
      end

      it 'creates a new provider' do
        expect {
          post '/api/v1/git/providers', params: valid_params, headers: headers, as: :json
        }.to change(Devops::GitProvider, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['provider']['name']).to eq('New Git Provider')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/git/providers',
             params: { provider: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/git/providers/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with git.providers.update permission' do
      it 'updates provider successfully' do
        patch "/api/v1/git/providers/#{provider.id}",
              params: { provider: { description: 'Updated description' } },
              headers: headers,
              as: :json

        expect_success_response

        provider.reload
        expect(provider.description).to eq('Updated description')
      end
    end
  end

  describe 'DELETE /api/v1/git/providers/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with git.providers.delete permission' do
      it 'deletes provider successfully' do
        provider_id = provider.id

        delete "/api/v1/git/providers/#{provider_id}", headers: headers, as: :json

        expect_success_response
        expect(Devops::GitProvider.find_by(id: provider_id)).to be_nil
      end
    end
  end

  describe 'GET /api/v1/git/providers/available' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:git_provider, 2, account: account)
      create(:git_provider, :inactive, account: account)
    end

    context 'with git.providers.read permission' do
      it 'returns only active providers' do
        get '/api/v1/git/providers/available', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['providers']).to be_an(Array)
        expect(response_data['data']['providers'].all? { |p| p['is_active'] != false }).to be true
      end

      it 'includes configured status' do
        get '/api/v1/git/providers/available', headers: headers, as: :json

        response_data = json_response
        first_provider = response_data['data']['providers'].first

        expect(first_provider).to have_key('configured')
      end
    end
  end

  # Nested credential endpoints
  describe 'GET /api/v1/git/providers/:id/credentials' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:git_provider, account: account) }

    before do
      create_list(:git_provider_credential, 2, account: account, provider: provider)
    end

    context 'with git.credentials.read permission' do
      it 'returns list of credentials for provider' do
        get "/api/v1/git/providers/#{provider.id}/credentials", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['credentials']).to be_an(Array)
        expect(response_data['data']['credentials'].length).to eq(2)
      end

      it 'includes credential details' do
        get "/api/v1/git/providers/#{provider.id}/credentials", headers: headers, as: :json

        response_data = json_response
        first_credential = response_data['data']['credentials'].first

        expect(first_credential).to include('id', 'name', 'is_active', 'is_default')
      end
    end
  end

  describe 'POST /api/v1/git/providers/:id/credentials' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:git_provider, account: account) }

    context 'with git.credentials.create permission' do
      let(:valid_params) do
        {
          credential: {
            name: 'New Test Credential',
            auth_type: 'personal_access_token',
            credentials: { token: 'test-token-123' }
          }
        }
      end

      before do
        allow_any_instance_of(Devops::Git::ProviderTestService).to receive(:test_connection).and_return(
          { success: true, username: 'testuser', user_id: '123', avatar_url: nil, scopes: [] }
        )
      end

      it 'creates a new credential' do
        expect {
          post "/api/v1/git/providers/#{provider.id}/credentials",
               params: valid_params,
               headers: headers,
               as: :json
        }.to change(Devops::GitProviderCredential, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['credential']['name']).to eq('New Test Credential')
      end
    end
  end

  describe 'DELETE /api/v1/git/providers/:id/credentials/:credential_id' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:git_provider, account: account) }
    # Create two credentials so the one being deleted isn't the only/default one
    let!(:other_credential) { create(:git_provider_credential, account: account, provider: provider, is_default: true) }
    let(:credential) { create(:git_provider_credential, account: account, provider: provider, is_default: false) }

    context 'with git.credentials.delete permission' do
      it 'deletes credential successfully' do
        credential_id = credential.id

        delete "/api/v1/git/providers/#{provider.id}/credentials/#{credential_id}",
               headers: headers,
               as: :json

        expect_success_response
        expect(Devops::GitProviderCredential.find_by(id: credential_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/git/providers/:id/credentials/:credential_id/test' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:git_provider, account: account) }
    let(:credential) { create(:git_provider_credential, account: account, provider: provider) }

    context 'with git.credentials.test permission' do
      it 'tests credential connection' do
        allow_any_instance_of(Devops::Git::ProviderTestService).to receive(:test_with_rate_limit).and_return(
          { success: true, message: 'Connection successful' }
        )

        post "/api/v1/git/providers/#{provider.id}/credentials/#{credential.id}/test",
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['success']).to be true
      end
    end
  end

  # Cross-tenant IDOR: a provider belongs_to :account (required), and create uses
  # current_user.account.git_providers. show/update/destroy must likewise scope to
  # the acting account so a foreign provider id 404s (no read/mutate/disclose).
  describe 'cross-account provider access (IDOR)' do
    let(:other_account) { create(:account) }
    let(:foreign_provider) { create(:git_provider, account: other_account) }

    it 'does not disclose a provider in another account (show)' do
      get "/api/v1/git/providers/#{foreign_provider.id}",
          headers: auth_headers_for(user_with_read_permission), as: :json

      expect_error_response('Provider not found', 404)
    end

    it 'does not update a provider in another account' do
      patch "/api/v1/git/providers/#{foreign_provider.id}",
            params: { provider: { description: 'hacked' } },
            headers: auth_headers_for(user_with_update_permission), as: :json

      expect_error_response('Provider not found', 404)
      expect(foreign_provider.reload.description).not_to eq('hacked')
    end

    it 'does not destroy a provider in another account' do
      foreign_provider # materialize before the request
      delete "/api/v1/git/providers/#{foreign_provider.id}",
             headers: auth_headers_for(user_with_delete_permission), as: :json

      expect_error_response('Provider not found', 404)
      expect(Devops::GitProvider.find_by(id: foreign_provider.id)).to be_present
    end
  end

  describe 'POST /api/v1/git/providers/:id/credentials/:credential_id/make_default' do
    let(:headers) { auth_headers_for(user_with_credential_permissions) }
    let(:provider) { create(:git_provider, account: account) }
    let(:credential) { create(:git_provider_credential, account: account, provider: provider, is_default: false) }

    context 'with git.credentials.update permission' do
      it 'makes credential default' do
        post "/api/v1/git/providers/#{provider.id}/credentials/#{credential.id}/make_default",
             headers: headers,
             as: :json

        expect_success_response

        credential.reload
        expect(credential.is_default).to be true
      end
    end
  end
end

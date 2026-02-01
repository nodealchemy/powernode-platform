# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Oauth::Applications', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['oauth.applications.read', 'oauth.applications.manage']) }
  let(:headers) { auth_headers_for(user) }

  let(:oauth_application) do
    create(:oauth_application,
           owner: account,
           name: 'Test App',
           scopes: 'read write',
           confidential: true)
  end

  describe 'GET /api/v1/oauth/applications' do
    let!(:app1) { create(:oauth_application, owner: account, name: 'App 1') }
    let!(:app2) { create(:oauth_application, owner: account, name: 'App 2') }
    let!(:other_app) { create(:oauth_application, name: 'Other App') }

    context 'with oauth.applications.read permission' do
      it 'returns list of applications for current account' do
        get '/api/v1/oauth/applications', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['applications']).to be_an(Array)
        expect(data['applications'].length).to eq(2)
        expect(data['applications'].map { |a| a['id'] }).to match_array([app1.id, app2.id])
      end

      it 'returns pagination metadata' do
        get '/api/v1/oauth/applications', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include(
          'current_page',
          'total_pages',
          'total_count',
          'per_page'
        )
      end

      it 'respects pagination parameters' do
        get '/api/v1/oauth/applications?page=1&per_page=1', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['applications'].length).to eq(1)
        expect(data['pagination']['per_page']).to eq(1)
      end
    end

    context 'without oauth.applications.read permission' do
      let(:user_without_permission) { create(:user, account: account, permissions: []) }
      let(:no_perm_headers) { auth_headers_for(user_without_permission) }

      it 'returns forbidden error' do
        get '/api/v1/oauth/applications', headers: no_perm_headers, as: :json

        expect_error_response('Permission denied: oauth.applications.read', 403)
      end
    end
  end

  describe 'GET /api/v1/oauth/applications/:id' do
    context 'with valid application' do
      it 'returns application details' do
        get "/api/v1/oauth/applications/#{oauth_application.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['application']).to include(
          'id' => oauth_application.id,
          'name' => 'Test App'
        )
        expect(data['application']['scopes']).to match_array(['read', 'write'])
      end

      it 'does not include secret in show response' do
        get "/api/v1/oauth/applications/#{oauth_application.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['application']).not_to have_key('secret')
      end
    end

    context 'with non-existent application' do
      it 'returns not found error' do
        get "/api/v1/oauth/applications/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('OAuth application not found', 404)
      end
    end
  end

  describe 'POST /api/v1/oauth/applications' do
    let(:application_params) do
      {
        application: {
          name: 'New Application',
          description: 'A test application',
          redirect_uri: 'https://example.com/callback',
          scopes: 'read write',
          confidential: true
        }
      }
    end

    context 'with oauth.applications.manage permission' do
      it 'creates application successfully' do
        expect do
          post '/api/v1/oauth/applications',
               params: application_params,
               headers: headers, as: :json
        end.to change(OauthApplication, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['application']).to include(
          'name' => 'New Application',
          'description' => 'A test application'
        )
        expect(data['application']).to have_key('secret')
      end

      it 'creates audit log entry' do
        expect do
          post '/api/v1/oauth/applications',
               params: application_params,
               headers: headers, as: :json
        end.to change(AuditLog, :count).by(1)

        audit = AuditLog.last
        expect(audit.action).to eq('oauth_application_created')
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors' do
        invalid_params = { application: { name: '' } }

        post '/api/v1/oauth/applications',
             params: invalid_params,
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PUT /api/v1/oauth/applications/:id' do
    let(:update_params) do
      {
        application: {
          name: 'Updated Name',
          description: 'Updated description'
        }
      }
    end

    it 'updates application successfully' do
      put "/api/v1/oauth/applications/#{oauth_application.id}",
          params: update_params,
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['application']).to include(
        'name' => 'Updated Name',
        'description' => 'Updated description'
      )
    end

    it 'creates audit log entry' do
      expect do
        put "/api/v1/oauth/applications/#{oauth_application.id}",
            params: update_params,
            headers: headers, as: :json
      end.to change(AuditLog, :count).by(1)

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_updated')
    end

    it 'prevents updating uid' do
      original_uid = oauth_application.uid

      put "/api/v1/oauth/applications/#{oauth_application.id}",
          params: { application: { uid: 'new_uid' } },
          headers: headers, as: :json

      expect_success_response
      expect(oauth_application.reload.uid).to eq(original_uid)
    end
  end

  describe 'DELETE /api/v1/oauth/applications/:id' do
    it 'deletes application successfully' do
      app_to_delete = create(:oauth_application, owner: account)

      expect do
        delete "/api/v1/oauth/applications/#{app_to_delete.id}",
               headers: headers, as: :json
      end.to change(OauthApplication, :count).by(-1)

      expect_success_response
    end

    it 'creates audit log entry' do
      app_to_delete = create(:oauth_application, owner: account)

      expect do
        delete "/api/v1/oauth/applications/#{app_to_delete.id}",
               headers: headers, as: :json
      end.to change(AuditLog, :count).by(1)

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_deleted')
    end
  end

  describe 'POST /api/v1/oauth/applications/:id/regenerate_secret' do
    it 'regenerates client secret' do
      original_secret = oauth_application.secret

      post "/api/v1/oauth/applications/#{oauth_application.id}/regenerate_secret",
           headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['secret']).to be_present
      expect(data['secret']).not_to eq(original_secret)
    end

    it 'creates audit log with high severity' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/regenerate_secret",
           headers: headers, as: :json

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_secret_regenerated')
      expect(audit.severity).to eq('high')
    end
  end

  describe 'POST /api/v1/oauth/applications/:id/suspend' do
    it 'suspends application successfully' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/suspend",
           params: { reason: 'Security violation' },
           headers: headers, as: :json

      expect_success_response
    end

    it 'creates audit log with high severity' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/suspend",
           params: { reason: 'Security violation' },
           headers: headers, as: :json

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_suspended')
      expect(audit.severity).to eq('high')
      expect(audit.metadata['reason']).to eq('Security violation')
    end
  end

  describe 'POST /api/v1/oauth/applications/:id/activate' do
    it 'activates application successfully' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/activate",
           headers: headers, as: :json

      expect_success_response
    end

    it 'creates audit log entry' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/activate",
           headers: headers, as: :json

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_activated')
    end
  end

  describe 'POST /api/v1/oauth/applications/:id/revoke' do
    it 'revokes application permanently' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/revoke",
           headers: headers, as: :json

      expect_success_response
    end

    it 'creates audit log with critical severity' do
      post "/api/v1/oauth/applications/#{oauth_application.id}/revoke",
           headers: headers, as: :json

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_application_revoked')
      expect(audit.severity).to eq('critical')
    end
  end

  describe 'GET /api/v1/oauth/applications/:id/tokens' do
    let!(:token1) { create(:oauth_access_token, oauth_app: oauth_application) }
    let!(:token2) { create(:oauth_access_token, oauth_app: oauth_application) }

    it 'returns list of access tokens' do
      get "/api/v1/oauth/applications/#{oauth_application.id}/tokens",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['tokens']).to be_an(Array)
      expect(data['tokens'].length).to eq(2)
    end

    it 'includes pagination metadata' do
      get "/api/v1/oauth/applications/#{oauth_application.id}/tokens",
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['pagination']).to include(
        'current_page',
        'total_pages',
        'total_count'
      )
    end
  end

  describe 'DELETE /api/v1/oauth/applications/:id/tokens' do
    let!(:active_token1) { create(:oauth_access_token, oauth_app: oauth_application, revoked_at: nil) }
    let!(:active_token2) { create(:oauth_access_token, oauth_app: oauth_application, revoked_at: nil) }
    let!(:revoked_token) { create(:oauth_access_token, oauth_app: oauth_application, revoked_at: 1.day.ago) }

    it 'revokes all active tokens' do
      delete "/api/v1/oauth/applications/#{oauth_application.id}/tokens",
             headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['revoked_count']).to eq(2)
    end

    it 'creates audit log entry' do
      expect do
        delete "/api/v1/oauth/applications/#{oauth_application.id}/tokens",
               headers: headers, as: :json
      end.to change(AuditLog, :count).by(1)

      audit = AuditLog.last
      expect(audit.action).to eq('oauth_tokens_bulk_revoked')
      expect(audit.metadata['tokens_revoked']).to eq(2)
    end
  end

  describe 'authentication' do
    it 'requires authentication for all endpoints' do
      get '/api/v1/oauth/applications', as: :json

      expect_error_response('Access token required', 401)
    end
  end
end

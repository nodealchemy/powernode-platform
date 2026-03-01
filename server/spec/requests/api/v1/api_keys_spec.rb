# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::ApiKeys', type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan, :with_limits) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_account_manage) { create(:user, account: account, permissions: [ 'account.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  before do
    create(:subscription, :active, account: account, plan: plan)
  end

  describe 'GET /api/v1/api_keys' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      create_list(:api_key, 3, account: account, created_by: admin_user)
    end

    context 'with admin access' do
      it 'returns paginated list of API keys' do
        get '/api/v1/api_keys', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['api_keys']).to be_an(Array)
        expect(response_data['data']['api_keys'].length).to eq(3)
      end

      it 'includes pagination metadata' do
        get '/api/v1/api_keys', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include(
          'current_page' => 1,
          'total_count' => 3
        )
      end

      it 'includes API key stats' do
        get '/api/v1/api_keys', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['stats']).to include(
          'total_keys',
          'active_keys'
        )
      end

      it 'respects per_page parameter' do
        get '/api/v1/api_keys', params: { per_page: 2 }, headers: headers

        response_data = json_response
        expect(response_data['data']['api_keys'].length).to eq(2)
      end

      it 'returns masked key values' do
        get '/api/v1/api_keys', headers: headers, as: :json

        response_data = json_response
        api_key_data = response_data['data']['api_keys'].first

        expect(api_key_data).to have_key('masked_key')
        expect(api_key_data).not_to have_key('key_value')
      end
    end

    context 'without admin access' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/api_keys', headers: headers, as: :json

        expect_error_response('Access denied: Admin privileges required', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/api_keys', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/api_keys/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, created_by: admin_user) }

    context 'with admin access' do
      it 'returns API key details' do
        get "/api/v1/api_keys/#{api_key.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => api_key.id,
          'name' => api_key.name
        )
      end

      it 'includes usage statistics' do
        get "/api/v1/api_keys/#{api_key.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('usage_stats')
      end

      it 'includes recent_usage' do
        get "/api/v1/api_keys/#{api_key.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('recent_usage')
      end
    end

    context 'when API key does not exist' do
      it 'returns not found error' do
        get '/api/v1/api_keys/nonexistent-id', headers: headers, as: :json

        expect_error_response('API key not found', 404)
      end
    end

    context 'when accessing other account API key without admin.access' do
      let(:other_account) { create(:account) }
      let(:other_api_key) { create(:api_key, account: other_account) }
      let(:headers) { auth_headers_for(user_with_account_manage) }

      it 'returns forbidden error' do
        get "/api/v1/api_keys/#{other_api_key.id}", headers: headers, as: :json

        expect_error_response('Access denied: You can only manage your account\'s API keys', 403)
      end
    end
  end

  describe 'POST /api/v1/api_keys' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin access' do
      let(:valid_params) do
        {
          api_key: {
            name: 'Test API Key',
            scopes: [ 'read', 'write' ]
          }
        }
      end

      it 'creates a new API key' do
        post '/api/v1/api_keys', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['name']).to eq('Test API Key')
      end

      it 'returns the full key_value on creation' do
        post '/api/v1/api_keys', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('key_value')
        expect(response_data['data']['key_value']).to be_present
      end

      it 'sets created_by to current user' do
        post '/api/v1/api_keys', params: valid_params, headers: headers, as: :json

        api_key = ApiKey.last
        expect(api_key.created_by).to eq(admin_user)
      end

      it 'creates audit log for API key creation' do
        expect {
          post '/api/v1/api_keys', params: valid_params, headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'api_key_created')
        expect(audit_log).to be_present
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/api_keys',
             params: { api_key: { name: '' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PUT /api/v1/api_keys/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, created_by: admin_user) }

    context 'with admin access' do
      it 'updates API key successfully' do
        put "/api/v1/api_keys/#{api_key.id}",
            params: { api_key: { name: 'Updated API Key' } },
            headers: headers,
            as: :json

        expect_success_response

        api_key.reload
        expect(api_key.name).to eq('Updated API Key')
      end

      it 'updates scopes' do
        put "/api/v1/api_keys/#{api_key.id}",
            params: { api_key: { scopes: [ 'admin' ] } },
            headers: headers,
            as: :json

        expect_success_response

        api_key.reload
        expect(api_key.scopes).to include('admin')
      end

      it 'creates audit log for update' do
        expect {
          put "/api/v1/api_keys/#{api_key.id}",
              params: { api_key: { name: 'Updated Key Name' } },
              headers: headers,
              as: :json
        }.to change(AuditLog, :count).by_at_least(1)
      end
    end
  end

  describe 'DELETE /api/v1/api_keys/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, created_by: admin_user) }

    context 'with admin access' do
      it 'deletes API key successfully' do
        api_key_id = api_key.id

        delete "/api/v1/api_keys/#{api_key_id}", headers: headers, as: :json

        expect_success_response
        expect(ApiKey.find_by(id: api_key_id)).to be_nil
      end

      it 'creates audit log for deletion' do
        expect {
          delete "/api/v1/api_keys/#{api_key.id}", headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'api_key_deleted')
        expect(audit_log).to be_present
      end
    end
  end

  describe 'POST /api/v1/api_keys/:id/regenerate' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, created_by: admin_user) }

    context 'with admin access' do
      it 'regenerates API key successfully' do
        old_masked = api_key.masked_key

        post "/api/v1/api_keys/#{api_key.id}/regenerate", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('key_value')
        expect(api_key.reload.masked_key).not_to eq(old_masked)
      end

      it 'returns the new full key value' do
        post "/api/v1/api_keys/#{api_key.id}/regenerate", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['key_value']).to be_present
      end

      it 'creates audit log for regeneration' do
        expect {
          post "/api/v1/api_keys/#{api_key.id}/regenerate", headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'api_key_regenerated')
        expect(audit_log).to be_present
      end
    end
  end

  describe 'POST /api/v1/api_keys/:id/toggle_status' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, is_active: true, created_by: admin_user) }

    context 'with admin access' do
      it 'toggles from active to revoked' do
        post "/api/v1/api_keys/#{api_key.id}/toggle_status", headers: headers, as: :json

        expect_success_response

        api_key.reload
        expect(api_key).not_to be_active
      end

      it 'toggles from revoked to active' do
        api_key.update!(is_active: false)

        post "/api/v1/api_keys/#{api_key.id}/toggle_status", headers: headers, as: :json

        expect_success_response

        api_key.reload
        expect(api_key).to be_active
      end

      it 'creates audit log for status change' do
        expect {
          post "/api/v1/api_keys/#{api_key.id}/toggle_status", headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)
      end
    end
  end

  describe 'GET /api/v1/api_keys/usage' do
    let(:headers) { auth_headers_for(admin_user) }

    it 'returns usage statistics' do
      get '/api/v1/api_keys/usage', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('usage_stats')
      expect(response_data['data']).to have_key('summary')
    end

    it 'accepts date range filters' do
      get '/api/v1/api_keys/usage',
          params: { date_from: 7.days.ago.to_date, date_to: Date.current },
          headers: headers

      expect_success_response
    end

    it 'can filter by specific api_key_id' do
      api_key = create(:api_key, account: account, created_by: admin_user)

      get '/api/v1/api_keys/usage',
          params: { api_key_id: api_key.id },
          headers: headers

      expect_success_response
    end
  end

  describe 'GET /api/v1/api_keys/scopes' do
    let(:headers) { auth_headers_for(admin_user) }

    it 'returns available scopes' do
      get '/api/v1/api_keys/scopes', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('scopes')
      expect(response_data['data']).to have_key('scope_descriptions')
    end
  end

  describe 'POST /api/v1/api_keys/validate' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:api_key) { create(:api_key, account: account, is_active: true, created_by: admin_user) }

    it 'validates a valid API key' do
      # Need to get the actual key value before hashing
      key_value = api_key.key_value

      post '/api/v1/api_keys/validate',
           params: { key: key_value },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['valid']).to be true
      expect(response_data['data']['id']).to eq(api_key.id)
    end

    it 'returns invalid for non-existent key' do
      post '/api/v1/api_keys/validate',
           params: { key: 'invalid-key-value' },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['valid']).to be false
    end

    it 'returns error when key is missing' do
      post '/api/v1/api_keys/validate',
           params: {},
           headers: headers,
           as: :json

      expect_error_response('API key required', 400)
    end

    it 'returns invalid reason for revoked key' do
      api_key.update!(is_active: false)

      post '/api/v1/api_keys/validate',
           params: { key: api_key.key_value },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['valid']).to be false
      expect(response_data['data']['reason']).to be_present
    end
  end
end

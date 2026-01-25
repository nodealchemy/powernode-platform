# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AdminSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_settings_view) { create(:user, account: account, permissions: ['admin.settings.view']) }
  let(:user_with_security_permission) { create(:user, account: account, permissions: ['admin.settings.view', 'admin.settings.security']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin_settings' do
    context 'with admin.settings.view permission' do
      let(:headers) { auth_headers_for(user_with_settings_view) }

      it 'returns admin overview' do
        get '/api/v1/admin_settings', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without required permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin_settings', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin_settings', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/admin_settings' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    context 'with admin.settings.view permission' do
      let(:valid_params) do
        {
          admin_settings: {
            maintenance_mode: false,
            registration_enabled: true,
            session_timeout_minutes: 60
          }
        }
      end

      it 'updates admin settings' do
        put '/api/v1/admin_settings',
            params: valid_params,
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['message']).to include('updated successfully')
      end
    end
  end

  describe 'GET /api/v1/admin_settings/users' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    before do
      create_list(:user, 3, account: account)
    end

    it 'returns users data' do
      get '/api/v1/admin_settings/users', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('users')
      expect(response_data['data']).to have_key('total_count')
      expect(response_data['data']).to have_key('active_count')
    end

    it 'includes user status counts' do
      get '/api/v1/admin_settings/users', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']).to include('active_count', 'inactive_count', 'suspended_count')
    end
  end

  describe 'GET /api/v1/admin_settings/accounts' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    it 'returns accounts data' do
      get '/api/v1/admin_settings/accounts', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('accounts')
      expect(response_data['data']).to have_key('total_count')
    end

    it 'includes account status counts' do
      get '/api/v1/admin_settings/accounts', headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']).to include('active_count', 'suspended_count', 'cancelled_count')
    end
  end

  describe 'GET /api/v1/admin_settings/system_logs' do
    let(:headers) { auth_headers_for(user_with_settings_view) }

    before do
      create_list(:audit_log, 5, account: account, user: admin_user, action: 'test_action')
    end

    it 'returns system logs' do
      get '/api/v1/admin_settings/system_logs', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('logs')
      expect(response_data['data']).to have_key('total_count')
    end
  end

  describe 'POST /api/v1/admin_settings/suspend_account' do
    let(:headers) { auth_headers_for(user_with_settings_view) }
    let(:target_account) { create(:account) }

    it 'suspends an account' do
      post '/api/v1/admin_settings/suspend_account',
           params: { account_id: target_account.id, reason: 'Violation of terms' },
           headers: headers,
           as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/admin_settings/activate_account' do
    let(:headers) { auth_headers_for(user_with_settings_view) }
    let(:target_account) { create(:account, status: 'suspended') }

    it 'activates a suspended account' do
      post '/api/v1/admin_settings/activate_account',
           params: { account_id: target_account.id, reason: 'Issue resolved' },
           headers: headers,
           as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security' do
    context 'with admin.settings.security permission' do
      let(:headers) { auth_headers_for(user_with_security_permission) }

      it 'returns security configuration' do
        get '/api/v1/admin_settings/security', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without security permission' do
      let(:headers) { auth_headers_for(user_with_settings_view) }

      it 'returns forbidden error' do
        get '/api/v1/admin_settings/security', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/admin_settings/security' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    context 'with admin.settings.security permission' do
      let(:security_params) do
        {
          security_config: {
            authentication: {
              max_failed_attempts: 5,
              lockout_duration: 30
            }
          }
        }
      end

      it 'updates security configuration' do
        put '/api/v1/admin_settings/security',
            params: security_params,
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/admin_settings/security/test' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    it 'tests security configuration' do
      post '/api/v1/admin_settings/security/test', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security/blacklist_stats' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    it 'returns blacklist statistics' do
      get '/api/v1/admin_settings/security/blacklist_stats', headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/admin_settings/security/audit_summary' do
    let(:headers) { auth_headers_for(user_with_security_permission) }

    it 'returns security audit summary' do
      get '/api/v1/admin_settings/security/audit_summary', headers: headers, as: :json

      expect_success_response
    end

    it 'accepts days parameter' do
      get '/api/v1/admin_settings/security/audit_summary',
          params: { days: 7 },
          headers: headers,
          as: :json

      expect_success_response
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SiteSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_settings_manage) { create(:user, account: account, permissions: ['settings.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/public/footer' do
    it 'returns footer data without authentication' do
      get '/api/v1/public/footer', as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('footer')
    end

    it 'includes default values' do
      get '/api/v1/public/footer', as: :json

      response_data = json_response
      footer = response_data['data']['footer']

      expect(footer).to have_key('site_name')
      expect(footer).to have_key('copyright_text')
    end
  end

  describe 'GET /api/v1/site_settings' do
    let(:headers) { auth_headers_for(admin_user) }

    before do
      create_list(:site_setting, 3)
    end

    context 'with admin access' do
      it 'returns list of settings' do
        get '/api/v1/site_settings', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['settings']).to be_an(Array)
        expect(response_data['data']['total_count']).to be >= 3
      end

      it 'includes setting details' do
        get '/api/v1/site_settings', headers: headers, as: :json

        response_data = json_response
        first_setting = response_data['data']['settings'].first

        expect(first_setting).to include('id', 'key', 'value', 'description', 'setting_type')
      end
    end

    context 'with settings.manage permission' do
      let(:headers) { auth_headers_for(user_with_settings_manage) }

      it 'returns settings list' do
        get '/api/v1/site_settings', headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without required permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/site_settings', headers: headers, as: :json

        expect_error_response('Permission denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/site_settings', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/site_settings/footer' do
    let(:headers) { auth_headers_for(admin_user) }

    it 'returns footer settings' do
      create(:site_setting, :footer_setting)

      get '/api/v1/site_settings/footer', headers: headers, as: :json

      expect_success_response
      expect(json_response['data']).to have_key('settings')
    end
  end

  describe 'GET /api/v1/site_settings/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:site_setting) { create(:site_setting) }

    context 'with admin access' do
      it 'returns setting details' do
        get "/api/v1/site_settings/#{site_setting.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['setting']).to include(
          'id' => site_setting.id,
          'key' => site_setting.key
        )
      end
    end

    context 'when setting does not exist' do
      it 'returns not found error' do
        get '/api/v1/site_settings/nonexistent-id', headers: headers, as: :json

        expect_error_response('Setting not found', 404)
      end
    end
  end

  describe 'POST /api/v1/site_settings' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin access' do
      let(:valid_params) do
        {
          site_setting: {
            key: 'new_setting',
            value: 'new_value',
            description: 'A new setting',
            setting_type: 'string',
            is_public: false
          }
        }
      end

      it 'creates a new setting' do
        expect {
          post '/api/v1/site_settings', params: valid_params, headers: headers, as: :json
        }.to change(SiteSetting, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['setting']['key']).to eq('new_setting')
      end

      it 'creates audit log for setting creation' do
        expect {
          post '/api/v1/site_settings', params: valid_params, headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'create_site_setting')
        expect(audit_log).to be_present
      end
    end

    context 'with invalid data' do
      it 'returns validation error for missing key' do
        post '/api/v1/site_settings',
             params: { site_setting: { value: 'test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PUT /api/v1/site_settings/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:site_setting) { create(:site_setting) }

    context 'with admin access' do
      it 'updates setting successfully' do
        put "/api/v1/site_settings/#{site_setting.id}",
            params: { site_setting: { value: 'updated_value' } },
            headers: headers,
            as: :json

        expect_success_response

        site_setting.reload
        expect(site_setting.value).to eq('updated_value')
      end

      it 'creates audit log for update' do
        expect {
          put "/api/v1/site_settings/#{site_setting.id}",
              params: { site_setting: { value: 'updated' } },
              headers: headers,
              as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'update_site_setting')
        expect(audit_log).to be_present
      end
    end
  end

  describe 'DELETE /api/v1/site_settings/:id' do
    let(:headers) { auth_headers_for(admin_user) }
    let(:site_setting) { create(:site_setting) }

    context 'with admin access' do
      it 'deletes setting successfully' do
        setting_id = site_setting.id

        delete "/api/v1/site_settings/#{setting_id}", headers: headers, as: :json

        expect_success_response
        expect(SiteSetting.find_by(id: setting_id)).to be_nil
      end

      it 'creates audit log for deletion' do
        expect {
          delete "/api/v1/site_settings/#{site_setting.id}", headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'delete_site_setting')
        expect(audit_log).to be_present
      end
    end
  end

  describe 'PUT /api/v1/site_settings/bulk_update' do
    let(:headers) { auth_headers_for(admin_user) }

    context 'with admin access' do
      let(:bulk_params) do
        {
          settings: {
            setting_one: { value: 'value1', setting_type: 'string' },
            setting_two: { value: 'value2', setting_type: 'string' }
          }
        }
      end

      it 'updates multiple settings' do
        put '/api/v1/site_settings/bulk_update',
            params: bulk_params,
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['settings']).to include('setting_one', 'setting_two')
      end

      it 'creates audit log for bulk update' do
        expect {
          put '/api/v1/site_settings/bulk_update',
              params: bulk_params,
              headers: headers,
              as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'bulk_update_site_settings')
        expect(audit_log).to be_present
      end
    end
  end
end

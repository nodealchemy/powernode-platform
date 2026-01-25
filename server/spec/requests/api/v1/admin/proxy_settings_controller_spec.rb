# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::ProxySettingsController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.access']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  describe 'GET /api/v1/admin/proxy_settings/url_config' do
    context 'with admin access permission' do
      it 'returns proxy URL configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          {
            enabled: true,
            default_protocol: 'https',
            default_host: 'api.example.com',
            trusted_hosts: ['example.com']
          }
        )

        get '/api/v1/admin/proxy_settings/url_config', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('enabled', 'default_protocol', 'default_host')
      end

      it 'handles service errors gracefully' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_raise(StandardError, 'Service error')

        get '/api/v1/admin/proxy_settings/url_config', headers: headers, as: :json

        expect_error_response('Failed to fetch proxy configuration', 200)
      end
    end

    context 'without admin access permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/proxy_settings/url_config', headers: non_admin_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/admin/proxy_settings/url_config' do
    context 'with admin access permission' do
      it 'updates proxy URL configuration' do
        updated_config = { enabled: true, default_protocol: 'https', default_host: 'new.example.com' }
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config).and_return(updated_config)

        put '/api/v1/admin/proxy_settings/url_config',
            params: { proxy_setting: { enabled: true, default_protocol: 'https', default_host: 'new.example.com' } }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('enabled', 'default_protocol', 'default_host')
      end
    end
  end

  describe 'POST /api/v1/admin/proxy_settings/validate_host' do
    context 'with admin access permission' do
      it 'validates a host successfully' do
        allow(AdminSetting).to receive(:validate_proxy_host).and_return(
          { valid: true, errors: [] }
        )

        post '/api/v1/admin/proxy_settings/validate_host',
             params: { host: 'example.com' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('host', 'validation', 'timestamp')
      end

      it 'returns error when host is blank' do
        post '/api/v1/admin/proxy_settings/validate_host',
             params: { host: '' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/admin/proxy_settings/test_headers' do
    context 'with admin access permission' do
      it 'tests proxy headers' do
        allow(AdminSetting).to receive(:test_proxy_headers).and_return(
          { valid: true, headers_count: 3 }
        )

        post '/api/v1/admin/proxy_settings/test_headers',
             params: { headers: { 'X-Custom-Header' => 'value' } }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('valid')
      end
    end
  end

  describe 'GET /api/v1/admin/proxy_settings/current_detection' do
    context 'with admin access permission' do
      it 'returns current proxy detection information' do
        get '/api/v1/admin/proxy_settings/current_detection', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('proxy_detected', 'proxy_context', 'request_headers', 'detection_timestamp')
      end
    end
  end

  describe 'POST /api/v1/admin/proxy_settings/trusted_hosts' do
    context 'with admin access permission' do
      it 'adds a trusted host successfully' do
        allow(AdminSetting).to receive(:validate_proxy_host).and_return({ valid: true, errors: [] })
        allow(AdminSetting).to receive(:add_trusted_host)
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { trusted_hosts: ['example.com', 'new-host.com'] }
        )

        post '/api/v1/admin/proxy_settings/trusted_hosts',
             params: { pattern: 'new-host.com' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('pattern', 'trusted_hosts')
      end

      it 'returns error when pattern is blank' do
        post '/api/v1/admin/proxy_settings/trusted_hosts',
             params: { pattern: '' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'validates wildcard pattern format' do
        post '/api/v1/admin/proxy_settings/trusted_hosts',
             params: { pattern: '*.invalid@pattern' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/admin/proxy_settings/trusted_hosts/:pattern' do
    context 'with admin access permission' do
      it 'removes a trusted host successfully' do
        allow(AdminSetting).to receive(:remove_trusted_host)
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { trusted_hosts: ['example.com'] }
        )

        delete '/api/v1/admin/proxy_settings/trusted_hosts/old-host.com', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('pattern', 'trusted_hosts')
      end

      it 'returns error when pattern is blank' do
        delete '/api/v1/admin/proxy_settings/trusted_hosts/', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /api/v1/admin/proxy_settings/trusted_hosts/reorder' do
    context 'with admin access permission' do
      it 'reorders trusted hosts successfully' do
        current_hosts = ['host1.com', 'host2.com', 'host3.com']
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return({ trusted_hosts: current_hosts })
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config)

        put '/api/v1/admin/proxy_settings/trusted_hosts/reorder',
            params: { trusted_hosts: ['host3.com', 'host1.com', 'host2.com'] }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('trusted_hosts')
      end

      it 'returns error when hosts array is blank' do
        put '/api/v1/admin/proxy_settings/trusted_hosts/reorder',
            params: { trusted_hosts: nil }.to_json,
            headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error when hosts do not match current set' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { trusted_hosts: ['host1.com', 'host2.com'] }
        )

        put '/api/v1/admin/proxy_settings/trusted_hosts/reorder',
            params: { trusted_hosts: ['host1.com', 'different.com'] }.to_json,
            headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/admin/proxy_settings/wildcard_patterns' do
    context 'with admin access permission' do
      it 'adds a wildcard pattern successfully' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { multi_tenancy: { wildcard_patterns: ['*.example.com'] } }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config)

        post '/api/v1/admin/proxy_settings/wildcard_patterns',
             params: { pattern: '*.newdomain.com' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('pattern', 'wildcard_patterns')
      end

      it 'returns error when pattern format is invalid' do
        post '/api/v1/admin/proxy_settings/wildcard_patterns',
             params: { pattern: 'invalid@pattern' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error when pattern already exists' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { multi_tenancy: { wildcard_patterns: ['*.example.com'] } }
        )

        post '/api/v1/admin/proxy_settings/wildcard_patterns',
             params: { pattern: '*.example.com' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/admin/proxy_settings/wildcard_patterns/:pattern' do
    context 'with admin access permission' do
      it 'removes a wildcard pattern successfully' do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { multi_tenancy: { wildcard_patterns: ['*.example.com', '*.other.com'] } }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config)

        delete '/api/v1/admin/proxy_settings/wildcard_patterns/*.example.com', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('pattern', 'wildcard_patterns')
      end
    end
  end

  describe 'PUT /api/v1/admin/proxy_settings/wildcard_patterns/reorder' do
    context 'with admin access permission' do
      it 'reorders wildcard patterns successfully' do
        current_patterns = ['*.host1.com', '*.host2.com']
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(
          { multi_tenancy: { wildcard_patterns: current_patterns } }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config)

        put '/api/v1/admin/proxy_settings/wildcard_patterns/reorder',
            params: { wildcard_patterns: ['*.host2.com', '*.host1.com'] }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('wildcard_patterns')
      end
    end
  end

  describe 'GET /api/v1/admin/proxy_settings/export' do
    context 'with admin access permission' do
      it 'exports proxy configuration' do
        config = { enabled: true, default_host: 'example.com' }
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_return(config)

        get '/api/v1/admin/proxy_settings/export', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('config', 'export_timestamp', 'export_format', 'version')
      end
    end
  end

  describe 'POST /api/v1/admin/proxy_settings/import' do
    context 'with admin access permission' do
      it 'imports proxy configuration successfully' do
        import_config = { enabled: true, default_host: 'imported.com' }
        allow(AdminSetting).to receive(:update_reverse_proxy_url_config).and_return(import_config)

        post '/api/v1/admin/proxy_settings/import',
             params: { config: import_config }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('enabled', 'default_host')
      end

      it 'returns error when config is blank' do
        post '/api/v1/admin/proxy_settings/import',
             params: { config: nil }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error when config is not a hash' do
        post '/api/v1/admin/proxy_settings/import',
             params: { config: 'invalid' }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end

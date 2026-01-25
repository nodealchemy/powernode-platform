# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::ReverseProxyController', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.settings.update']) }
  let(:non_admin_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:non_admin_headers) { auth_headers_for(non_admin_user) }

  describe 'GET /api/v1/admin/reverse_proxy' do
    context 'with admin settings update permission' do
      it 'returns reverse proxy configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return({ enabled: true })
        allow(AdminSetting).to receive(:service_discovery_config).and_return({ enabled: false })
        allow(AdminSetting).to receive(:service_templates).and_return([])
        allow(AdminSetting).to receive(:proxy_health_status).and_return({ status: 'healthy' })

        get '/api/v1/admin/reverse_proxy', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('reverse_proxy_config', 'service_discovery_config', 'service_templates', 'health_status')
      end

      it 'handles service errors gracefully' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_raise(StandardError, 'Service error')

        get '/api/v1/admin/reverse_proxy', headers: headers, as: :json

        expect_error_response('Failed to fetch reverse proxy configuration', 500)
      end
    end

    context 'without admin settings update permission' do
      it 'returns forbidden error' do
        get '/api/v1/admin/reverse_proxy', headers: non_admin_headers, as: :json

        expect_error_response('Insufficient permissions to manage reverse proxy settings', 403)
      end
    end
  end

  describe 'PUT /api/v1/admin/reverse_proxy' do
    context 'with admin settings update permission' do
      it 'updates reverse proxy configuration' do
        allow(AdminSetting).to receive(:update_reverse_proxy_config)

        put '/api/v1/admin/reverse_proxy',
            params: {
              config_type: 'reverse_proxy_config',
              reverse_proxy_config: { enabled: true }
            }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Reverse proxy configuration updated successfully')
      end

      it 'returns error for invalid config type' do
        put '/api/v1/admin/reverse_proxy',
            params: { config_type: 'invalid_type' }.to_json,
            headers: headers

        expect_error_response('Invalid configuration type', 400)
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/test' do
    context 'with admin settings update permission' do
      it 'starts configuration test successfully' do
        allow_any_instance_of(Api::V1::Admin::ReverseProxyController).to receive(:validate_proxy_config).and_return(
          { valid: true, errors: [] }
        )

        # Mock the job class
        job_class = double('JobClass')
        allow(job_class).to receive(:perform_async).and_return('sidekiq-job-id')
        allow_any_instance_of(Api::V1::Admin::ReverseProxyController).to receive(:get_job_class).and_return(job_class)

        allow(BackgroundJob).to receive(:create_for_sidekiq_job).and_return(
          double('BackgroundJob', id: 'bg-job-id')
        )

        post '/api/v1/admin/reverse_proxy/test',
             params: { test_config: { enabled: true } }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('job_id', 'status', 'message')
      end

      it 'returns error when configuration is invalid' do
        allow_any_instance_of(Api::V1::Admin::ReverseProxyController).to receive(:validate_proxy_config).and_return(
          { valid: false, errors: ['Missing required field'] }
        )

        post '/api/v1/admin/reverse_proxy/test',
             params: { test_config: { enabled: true } }.to_json,
             headers: headers

        expect_error_response(/Configuration validation failed/, 422)
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/generate_config' do
    context 'with admin settings update permission' do
      it 'generates nginx configuration successfully' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return({ enabled: true })

        job_class = double('JobClass')
        allow(job_class).to receive(:perform_async).and_return('sidekiq-job-id')
        allow_any_instance_of(Api::V1::Admin::ReverseProxyController).to receive(:get_job_class).and_return(job_class)

        allow(BackgroundJob).to receive(:create_for_sidekiq_job).and_return(
          double('BackgroundJob', id: 'bg-job-id')
        )

        post '/api/v1/admin/reverse_proxy/generate_config',
             params: { proxy_type: 'nginx' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('job_id', 'proxy_type', 'message')
      end

      it 'returns error for unsupported proxy type' do
        post '/api/v1/admin/reverse_proxy/generate_config',
             params: { proxy_type: 'unsupported' }.to_json,
             headers: headers

        expect_error_response(/Unsupported proxy type/, 400)
      end
    end
  end

  describe 'GET /api/v1/admin/reverse_proxy/health' do
    context 'with admin settings update permission' do
      it 'returns health status' do
        allow(AdminSetting).to receive(:proxy_health_status).and_return(
          { status: 'healthy', services: { frontend: 'up', backend: 'up' } }
        )

        get '/api/v1/admin/reverse_proxy/health', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('status', 'services')
      end
    end
  end

  describe 'GET /api/v1/admin/reverse_proxy/status' do
    context 'with admin settings update permission' do
      it 'returns reverse proxy status' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          {
            'enabled' => true,
            'current_environment' => 'production',
            'environments' => { 'production' => { 'frontend' => {}, 'backend' => {} } }
          }
        )
        allow(AdminSetting).to receive(:sorted_url_mappings).and_return([])
        allow(AdminSetting).to receive(:find_by).and_return(double('AdminSetting', updated_at: Time.current))

        get '/api/v1/admin/reverse_proxy/status', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('enabled', 'current_environment', 'active_mappings')
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/url_mappings' do
    context 'with admin settings update permission' do
      it 'creates a new URL mapping' do
        allow(AdminSetting).to receive(:add_url_mapping)

        post '/api/v1/admin/reverse_proxy/url_mappings',
             params: {
               url_mapping: {
                 name: 'API Routes',
                 pattern: '/api/*',
                 target_service: 'backend',
                 priority: 10
               }
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('message', 'mapping')
      end
    end
  end

  describe 'PUT /api/v1/admin/reverse_proxy/url_mappings/:id' do
    context 'with admin settings update permission' do
      it 'updates a URL mapping' do
        allow(AdminSetting).to receive(:update_url_mapping)

        put '/api/v1/admin/reverse_proxy/url_mappings/123',
            params: {
              url_mapping: {
                name: 'Updated Mapping',
                priority: 15
              }
            }.to_json,
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('URL mapping updated successfully')
      end
    end
  end

  describe 'DELETE /api/v1/admin/reverse_proxy/url_mappings/:id' do
    context 'with admin settings update permission' do
      it 'removes a URL mapping' do
        allow(AdminSetting).to receive(:remove_url_mapping)

        delete '/api/v1/admin/reverse_proxy/url_mappings/123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('URL mapping removed successfully')
      end
    end
  end

  describe 'PATCH /api/v1/admin/reverse_proxy/url_mappings/:id/toggle' do
    context 'with admin settings update permission' do
      it 'toggles URL mapping enabled state' do
        allow(AdminSetting).to receive(:toggle_url_mapping)

        patch '/api/v1/admin/reverse_proxy/url_mappings/123/toggle',
              params: { enabled: true }.to_json,
              headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('URL mapping enabled successfully')
      end
    end
  end

  describe 'GET /api/v1/admin/reverse_proxy/discovered_services' do
    context 'with admin settings update permission' do
      it 'returns list of discovered services' do
        get '/api/v1/admin/reverse_proxy/discovered_services', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/service_discovery' do
    context 'with admin settings update permission' do
      it 'starts service discovery' do
        allow(AdminSetting).to receive(:service_discovery_config).and_return(
          { 'enabled' => true, 'methods' => ['dns', 'consul'] }
        )

        job_class = double('JobClass')
        allow(job_class).to receive(:perform_async).and_return('sidekiq-job-id')
        allow_any_instance_of(Api::V1::Admin::ReverseProxyController).to receive(:get_job_class).and_return(job_class)

        allow(BackgroundJob).to receive(:create_for_sidekiq_job).and_return(
          double('BackgroundJob', id: 'bg-job-id')
        )

        post '/api/v1/admin/reverse_proxy/service_discovery', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('job_id', 'status', 'methods')
      end

      it 'returns error when service discovery is disabled' do
        allow(AdminSetting).to receive(:service_discovery_config).and_return(
          { 'enabled' => false }
        )

        post '/api/v1/admin/reverse_proxy/service_discovery', headers: headers, as: :json

        expect_error_response('Service discovery is not enabled', 422)
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/add_discovered_service' do
    context 'with admin settings update permission' do
      it 'adds a discovered service to configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          { 'current_environment' => 'production', 'environments' => { 'production' => {} } }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_config)

        post '/api/v1/admin/reverse_proxy/add_discovered_service',
             params: {
               service: {
                 name: 'new-service',
                 host: 'localhost',
                 port: 8080,
                 protocol: 'http',
                 health_check_path: '/health'
               }
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('Service new-service added to configuration')
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/test_service' do
    context 'with admin settings update permission' do
      it 'tests service connectivity' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          {
            'environments' => {
              'production' => {
                'frontend' => {
                  'host' => 'localhost',
                  'port' => 3000,
                  'base_url' => 'http://localhost:3000',
                  'health_check_path' => '/health'
                }
              }
            }
          }
        )

        post '/api/v1/admin/reverse_proxy/test_service',
             params: { environment: 'production', service_name: 'frontend' }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('status')
      end

      it 'returns error when service is not found' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          { 'environments' => { 'production' => {} } }
        )

        post '/api/v1/admin/reverse_proxy/test_service',
             params: { environment: 'production', service_name: 'nonexistent' }.to_json,
             headers: headers

        expect_error_response('Service not found in configuration', 404)
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/validate_service' do
    context 'with admin settings update permission' do
      it 'validates service configuration' do
        post '/api/v1/admin/reverse_proxy/validate_service',
             params: {
               service_config: {
                 host: 'example.com',
                 port: 8080,
                 protocol: 'http',
                 health_check_path: '/health'
               }
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('valid', 'errors', 'warnings')
      end

      it 'detects invalid configuration' do
        post '/api/v1/admin/reverse_proxy/validate_service',
             params: {
               service_config: {
                 host: '',
                 port: 99999,
                 protocol: 'invalid'
               }
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be false
        expect(data['errors']).not_to be_empty
      end
    end
  end

  describe 'GET /api/v1/admin/reverse_proxy/service_templates' do
    context 'with admin settings update permission' do
      it 'returns service templates' do
        get '/api/v1/admin/reverse_proxy/service_templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.first).to include('name', 'type', 'description', 'config')
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/duplicate_service' do
    context 'with admin settings update permission' do
      it 'duplicates a service configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          {
            'environments' => {
              'production' => {
                'frontend' => {
                  'host' => 'localhost',
                  'port' => 3000,
                  'protocol' => 'http',
                  'base_url' => 'http://localhost:3000'
                }
              }
            }
          }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_config)

        post '/api/v1/admin/reverse_proxy/duplicate_service',
             params: {
               environment: 'production',
               service_name: 'frontend',
               new_name: 'frontend-2'
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data['message']).to include('duplicated')
      end

      it 'returns error when source service not found' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          { 'environments' => { 'production' => {} } }
        )

        post '/api/v1/admin/reverse_proxy/duplicate_service',
             params: {
               environment: 'production',
               service_name: 'nonexistent',
               new_name: 'new-service'
             }.to_json,
             headers: headers

        expect_error_response('Source service not found', 404)
      end
    end
  end

  describe 'GET /api/v1/admin/reverse_proxy/export_services/:environment' do
    context 'with admin settings update permission' do
      it 'exports services configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          { 'environments' => { 'production' => { 'frontend' => {}, 'backend' => {} } } }
        )

        get '/api/v1/admin/reverse_proxy/export_services/production', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('environment', 'services', 'export_format', 'filename')
      end
    end
  end

  describe 'POST /api/v1/admin/reverse_proxy/import_services' do
    context 'with admin settings update permission' do
      it 'imports services configuration' do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(
          { 'environments' => { 'production' => {} } }
        )
        allow(AdminSetting).to receive(:update_reverse_proxy_config)

        post '/api/v1/admin/reverse_proxy/import_services',
             params: {
               environment: 'production',
               services: {
                 'new-service' => {
                   'host' => 'localhost',
                   'port' => 8080,
                   'protocol' => 'http'
                 }
               }
             }.to_json,
             headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include('imported_count', 'skipped_count', 'message')
      end
    end
  end
end

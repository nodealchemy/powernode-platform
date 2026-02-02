# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Services', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:regular_user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(admin_user) }
  let(:regular_headers) { auth_headers_for(regular_user) }

  before do
    admin_user.grant_permission('admin.settings.update')
  end

  describe 'GET /api/v1/services' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:get_full_config).and_return(
        {
          enabled: true,
          current_environment: 'development',
          url_mappings: []
        }
      )
    end

    context 'with admin permission' do
      it 'returns proxy configuration' do
        get '/api/v1/services', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('enabled', 'current_environment')
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        get '/api/v1/services', headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect_error_response('Insufficient permissions to manage services settings')
      end
    end
  end

  describe 'PUT /api/v1/services' do
    let(:config_params) do
      {
        config_type: 'service_config',
        service_config: {
          enabled: true,
          current_environment: 'production'
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:update_config).and_return(
        double(success?: true, data: { enabled: true })
      )
    end

    it 'updates proxy configuration' do
      put '/api/v1/services', params: config_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('enabled')
    end

    context 'with invalid config type' do
      let(:invalid_params) { { config_type: 'invalid_type' } }

      it 'returns bad request error' do
        put '/api/v1/services', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response('Invalid configuration type')
      end
    end
  end

  describe 'POST /api/v1/services/test_configuration' do
    let(:test_config) { { enabled: true, services: [] } }

    before do
      allow(AdminSetting).to receive(:reverse_proxy_config).and_return(test_config)
      allow_any_instance_of(Services::ProxyConfigService).to receive(:validate_config).and_return(
        { valid: true }
      )
      allow_any_instance_of(Api::V1::ServicesController).to receive(:enqueue_job).and_return(
        { job_id: SecureRandom.uuid, sidekiq_jid: 'test-jid', status: 'started' }
      )
    end

    it 'tests the configuration' do
      post '/api/v1/services/test_configuration', params: { test_config: test_config }, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('status')
    end

    context 'with invalid configuration' do
      before do
        allow_any_instance_of(Services::ProxyConfigService).to receive(:validate_config).and_return(
          { valid: false, errors: [ 'Invalid config' ] }
        )
      end

      it 'returns validation errors' do
        post '/api/v1/services/test_configuration', params: { test_config: test_config }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response
      end
    end
  end

  describe 'POST /api/v1/services/generate_config' do
    let(:generate_params) { { proxy_type: 'nginx' } }

    before do
      allow(AdminSetting).to receive(:reverse_proxy_config).and_return({})
      allow_any_instance_of(Services::ProxyConfigService).to receive(:valid_proxy_type?).and_return(true)
      allow_any_instance_of(Api::V1::ServicesController).to receive(:enqueue_job).and_return(
        { job_id: SecureRandom.uuid, sidekiq_jid: 'test-jid', status: 'started' }
      )
    end

    it 'generates configuration for specified proxy type' do
      post '/api/v1/services/generate_config', params: generate_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('status')
      expect(data['proxy_type']).to eq('nginx')
    end

    context 'with unsupported proxy type' do
      before do
        allow_any_instance_of(Services::ProxyConfigService).to receive(:valid_proxy_type?).and_return(false)
      end

      it 'returns bad request error' do
        post '/api/v1/services/generate_config',
             params: { proxy_type: 'unsupported' },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response
      end
    end
  end

  describe 'GET /api/v1/services/health_check' do
    before do
      allow(AdminSetting).to receive(:proxy_health_status).and_return(
        {
          status: 'healthy',
          services: [],
          last_check: Time.current
        }
      )
    end

    it 'returns health status' do
      get '/api/v1/services/health_check', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('status', 'services')
    end
  end

  describe 'GET /api/v1/services/status' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:get_status).and_return(
        {
          running: true,
          uptime: 3600,
          connections: 10
        }
      )
    end

    it 'returns service status' do
      get '/api/v1/services/status', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('running')
    end
  end

  describe 'POST /api/v1/services/url_mappings' do
    let(:mapping_params) do
      {
        url_mapping: {
          name: 'API Mapping',
          pattern: '/api/*',
          target_service: 'backend',
          priority: 1,
          enabled: true
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:create_url_mapping).and_return(
        {
          'id' => SecureRandom.uuid,
          'pattern' => '/api/*',
          'target_service' => 'backend'
        }
      )
    end

    it 'creates a URL mapping' do
      post '/api/v1/services/url_mappings', params: mapping_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('mapping')
    end
  end

  describe 'PUT /api/v1/services/url_mappings/:id/update_url_mapping' do
    let(:mapping_id) { SecureRandom.uuid }
    let(:update_params) do
      {
        url_mapping: {
          name: 'Updated Mapping',
          priority: 2
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:update_url_mapping).and_return(true)
    end

    it 'updates the URL mapping' do
      put "/api/v1/services/url_mappings/#{mapping_id}/update_url_mapping",
          params: update_params,
          headers: headers,
          as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('URL mapping updated successfully')
    end
  end

  describe 'DELETE /api/v1/services/url_mappings/:id' do
    let(:mapping_id) { SecureRandom.uuid }

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:remove_url_mapping).and_return(true)
    end

    it 'removes the URL mapping' do
      delete "/api/v1/services/url_mappings/#{mapping_id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('URL mapping removed successfully')
    end
  end

  describe 'PATCH /api/v1/services/url_mappings/:id/toggle' do
    let(:mapping_id) { SecureRandom.uuid }

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:toggle_url_mapping).and_return(true)
    end

    it 'toggles the URL mapping' do
      patch "/api/v1/services/url_mappings/#{mapping_id}/toggle",
            params: { enabled: true },
            headers: headers,
            as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to include('enabled successfully')
    end
  end

  describe 'GET /api/v1/services/discovered_services' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:discovered_services).and_return(
        [
          { name: 'service1', host: 'localhost', port: 3000 },
          { name: 'service2', host: 'localhost', port: 4000 }
        ]
      )
    end

    it 'returns discovered services' do
      get '/api/v1/services/discovered_services', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(2)
    end
  end

  describe 'POST /api/v1/services/service_discovery' do
    before do
      allow(AdminSetting).to receive(:service_discovery_config).and_return(
        {
          'enabled' => true,
          'methods' => [ 'dns', 'port_scan' ]
        }
      )
    end

    it 'starts service discovery' do
      allow_any_instance_of(Api::V1::ServicesController).to receive(:enqueue_job).and_return(
        { job_id: SecureRandom.uuid, sidekiq_jid: 'test-jid', status: 'started' }
      )

      post '/api/v1/services/service_discovery', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('status')
      expect(data['message']).to include('Service discovery started')
    end

    context 'with service discovery disabled' do
      before do
        allow(AdminSetting).to receive(:service_discovery_config).and_return(
          { 'enabled' => false }
        )
      end

      it 'returns error' do
        post '/api/v1/services/service_discovery', headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response('Service discovery is not enabled')
      end
    end
  end

  describe 'POST /api/v1/services/add_discovered_service' do
    let(:service_params) do
      {
        service: {
          name: 'new_service',
          host: 'localhost',
          port: 5000,
          protocol: 'http'
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:add_service).and_return(
        double(success?: true, data: { name: 'new_service' })
      )
    end

    it 'adds a discovered service' do
      post '/api/v1/services/add_discovered_service',
           params: service_params,
           headers: headers,
           as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('name')
    end
  end

  describe 'GET /api/v1/services/health_history/:service_name' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:health_history).and_return(
        [
          { timestamp: 1.hour.ago, status: 'healthy' },
          { timestamp: 2.hours.ago, status: 'healthy' }
        ]
      )
    end

    it 'returns health history for service' do
      get '/api/v1/services/health_history/backend', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
    end
  end

  describe 'POST /api/v1/services/test_service' do
    let(:test_params) do
      {
        environment: 'development',
        service_name: 'backend'
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:test_service).and_return(
        {
          status: 'healthy',
          response_time: 50
        }
      )
    end

    it 'tests a service' do
      post '/api/v1/services/test_service', params: test_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('status')
    end
  end

  describe 'POST /api/v1/services/validate_service' do
    let(:validation_params) do
      {
        service_config: {
          host: 'localhost',
          port: 3000,
          protocol: 'http'
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:validate_service).and_return(
        { valid: true }
      )
    end

    it 'validates service configuration' do
      post '/api/v1/services/validate_service',
           params: validation_params,
           headers: headers,
           as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('valid')
    end
  end

  describe 'GET /api/v1/services/service_templates' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:service_templates).and_return(
        {
          nginx: { enabled: true, config_path: '/etc/nginx' },
          apache: { enabled: false, config_path: '/etc/apache2' }
        }
      )
    end

    it 'returns service templates' do
      get '/api/v1/services/service_templates', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('nginx')
      expect(data).to have_key('apache')
    end
  end

  describe 'POST /api/v1/services/duplicate_service' do
    let(:duplicate_params) do
      {
        environment: 'development',
        service_name: 'backend',
        new_name: 'backend_copy'
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:duplicate_service).and_return(
        double(success?: true, data: { name: 'backend_copy' })
      )
    end

    it 'duplicates a service' do
      post '/api/v1/services/duplicate_service',
           params: duplicate_params,
           headers: headers,
           as: :json

      expect_success_response
      data = json_response_data
      expect(data['name']).to eq('backend_copy')
    end
  end

  describe 'GET /api/v1/services/export_services/:environment' do
    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:export_services).and_return(
        {
          environment: 'development',
          services: []
        }
      )
    end

    it 'exports services configuration' do
      get '/api/v1/services/export_services/development', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('environment')
      expect(data).to have_key('services')
    end
  end

  describe 'POST /api/v1/services/import_services' do
    let(:import_params) do
      {
        environment: 'development',
        services: {
          'backend' => { host: 'localhost', port: 3000 }
        }
      }
    end

    before do
      allow_any_instance_of(Services::ProxyConfigService).to receive(:import_services).and_return(
        { imported: 1, skipped: 0 }
      )
    end

    it 'imports services configuration' do
      post '/api/v1/services/import_services',
           params: import_params,
           headers: headers,
           as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('imported')
    end
  end
end

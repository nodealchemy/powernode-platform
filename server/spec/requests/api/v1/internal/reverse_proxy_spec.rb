# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::ReverseProxy', type: :request do
  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:valid_config) do
    {
      enabled: true,
      environments: {
        development: {
          frontend: { host: 'localhost', port: 5173, protocol: 'http' },
          backend: { host: 'localhost', port: 3000, protocol: 'http' }
        }
      },
      url_mappings: [
        { pattern: '/api', target_service: 'backend', priority: 1 }
      ]
    }
  end

  describe 'POST /api/v1/internal/reverse_proxy/validate' do
    context 'with internal authentication' do
      it 'validates valid proxy configuration' do
        post '/api/v1/internal/reverse_proxy/validate',
             headers: internal_headers,
             params: { config: valid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['valid']).to be true
        expect(response_data['data']['data']['errors']).to be_empty
      end

      it 'detects missing enabled field' do
        invalid_config = valid_config.dup
        invalid_config.delete(:enabled)

        post '/api/v1/internal/reverse_proxy/validate',
             headers: internal_headers,
             params: { config: invalid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['valid']).to be false
        expect(response_data['data']['data']['errors']).to include('Missing enabled field')
      end

      it 'detects missing environments configuration' do
        invalid_config = valid_config.dup
        invalid_config.delete(:environments)

        post '/api/v1/internal/reverse_proxy/validate',
             headers: internal_headers,
             params: { config: invalid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['valid']).to be false
        expect(response_data['data']['data']['errors']).to include('Missing environments configuration')
      end

      it 'detects missing url_mappings configuration' do
        invalid_config = valid_config.dup
        invalid_config.delete(:url_mappings)

        post '/api/v1/internal/reverse_proxy/validate',
             headers: internal_headers,
             params: { config: invalid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['valid']).to be false
        expect(response_data['data']['data']['errors']).to include('Missing url_mappings configuration')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/reverse_proxy/validate',
             params: { config: valid_config },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/reverse_proxy/test_connectivity' do
    context 'with internal authentication' do
      it 'tests connectivity to configured services' do
        post '/api/v1/internal/reverse_proxy/test_connectivity',
             headers: internal_headers,
             params: { config: valid_config.merge(current_environment: 'development') },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']).to have_key('frontend')
        expect(response_data['data']['data']).to have_key('backend')
      end
    end
  end

  describe 'POST /api/v1/internal/reverse_proxy/generate_config' do
    context 'with internal authentication' do
      it 'generates nginx configuration' do
        post '/api/v1/internal/reverse_proxy/generate_config',
             headers: internal_headers,
             params: { proxy_type: 'nginx', config: valid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['config']).to include('upstream')
        expect(response_data['data']['data']['filename']).to eq('powernode_nginx.conf')
        expect(response_data['data']['data']['instructions']).to be_present
      end

      it 'returns error for unsupported proxy type' do
        post '/api/v1/internal/reverse_proxy/generate_config',
             headers: internal_headers,
             params: { proxy_type: 'unsupported', config: valid_config },
             as: :json

        expect(response).to have_http_status(:internal_server_error)
      end

      it 'includes apache placeholder for apache type' do
        post '/api/v1/internal/reverse_proxy/generate_config',
             headers: internal_headers,
             params: { proxy_type: 'apache', config: valid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['config']).to include('Apache configuration generation not implemented')
      end

      it 'includes traefik placeholder for traefik type' do
        post '/api/v1/internal/reverse_proxy/generate_config',
             headers: internal_headers,
             params: { proxy_type: 'traefik', config: valid_config },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['config']).to include('Traefik configuration generation not implemented')
      end
    end
  end

  describe 'POST /api/v1/internal/reverse_proxy/service_discovery' do
    context 'with internal authentication' do
      it 'requires service discovery to be enabled' do
        discovery_config = { enabled: false, methods: [] }

        post '/api/v1/internal/reverse_proxy/service_discovery',
             headers: internal_headers,
             params: { discovery_config: discovery_config },
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'discovers services via DNS' do
        discovery_config = {
          enabled: true,
          methods: ['dns'],
          dns_config: { enabled: true }
        }

        post '/api/v1/internal/reverse_proxy/service_discovery',
             headers: internal_headers,
             params: { discovery_config: discovery_config },
             as: :json

        expect_success_response
        response_data = json_response

        services = response_data['data']['data']['services']
        expect(services).to be_an(Array)
        expect(services.any? { |s| s[:discovered_method] == 'dns' }).to be true
      end

      it 'discovers services via consul' do
        discovery_config = {
          enabled: true,
          methods: ['consul'],
          consul_config: { enabled: true }
        }

        post '/api/v1/internal/reverse_proxy/service_discovery',
             headers: internal_headers,
             params: { discovery_config: discovery_config },
             as: :json

        expect_success_response
        response_data = json_response

        services = response_data['data']['data']['services']
        expect(services.any? { |s| s[:discovered_method] == 'consul' }).to be true
      end

      it 'discovers services via port scan' do
        discovery_config = {
          enabled: true,
          methods: ['port_scan'],
          port_scan_config: {
            enabled: true,
            port_ranges: { backend: [3000, 3100] }
          }
        }

        post '/api/v1/internal/reverse_proxy/service_discovery',
             headers: internal_headers,
             params: { discovery_config: discovery_config },
             as: :json

        expect_success_response
        response_data = json_response

        services = response_data['data']['data']['services']
        expect(services.any? { |s| s[:discovered_method] == 'port_scan' }).to be true
      end

      it 'discovers services via kubernetes' do
        discovery_config = {
          enabled: true,
          methods: ['kubernetes'],
          kubernetes_config: { enabled: true }
        }

        post '/api/v1/internal/reverse_proxy/service_discovery',
             headers: internal_headers,
             params: { discovery_config: discovery_config },
             as: :json

        expect_success_response
        response_data = json_response

        services = response_data['data']['data']['services']
        expect(services.any? { |s| s[:discovered_method] == 'kubernetes' }).to be true
      end
    end
  end

  describe 'POST /api/v1/internal/reverse_proxy/health_check' do
    context 'with internal authentication' do
      before do
        allow(AdminSetting).to receive(:reverse_proxy_config).and_return(valid_config)
      end

      it 'checks health of all services in environment' do
        post '/api/v1/internal/reverse_proxy/health_check',
             headers: internal_headers,
             params: { environment: 'development' },
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['services']).to be_a(Hash)
        expect(response_data['data']['data']['environment']).to eq('development')
      end

      it 'checks health of specific service' do
        post '/api/v1/internal/reverse_proxy/health_check',
             headers: internal_headers,
             params: { environment: 'development', service: 'frontend' },
             as: :json

        expect_success_response
        response_data = json_response

        services = response_data['data']['data']['services']
        expect(services).to have_key('frontend')
      end
    end
  end

  describe 'POST /api/v1/internal/reverse_proxy/validate_services' do
    context 'with internal authentication' do
      it 'validates service configurations' do
        services = {
          frontend: { host: 'localhost', port: 5173, protocol: 'http', health_check_path: '/health' },
          backend: { host: 'api.local', port: 3000, protocol: 'https', health_check_path: '/api/health' }
        }

        post '/api/v1/internal/reverse_proxy/validate_services',
             headers: internal_headers,
             params: { services: services },
             as: :json

        expect_success_response
        response_data = json_response

        validations = response_data['data']['data']['validations']
        expect(validations).to have_key('frontend')
        expect(validations).to have_key('backend')
        expect(validations['frontend']['valid']).to be true
        expect(validations['backend']['valid']).to be true
      end

      it 'detects invalid host' do
        services = {
          invalid: { host: '', port: 3000, protocol: 'http' }
        }

        post '/api/v1/internal/reverse_proxy/validate_services',
             headers: internal_headers,
             params: { services: services },
             as: :json

        expect_success_response
        response_data = json_response

        validation = response_data['data']['data']['validations']['invalid']
        expect(validation['valid']).to be false
        expect(validation['errors']).to include('Host is required')
      end

      it 'detects invalid port' do
        services = {
          invalid: { host: 'localhost', port: 99999, protocol: 'http' }
        }

        post '/api/v1/internal/reverse_proxy/validate_services',
             headers: internal_headers,
             params: { services: services },
             as: :json

        expect_success_response
        response_data = json_response

        validation = response_data['data']['data']['validations']['invalid']
        expect(validation['valid']).to be false
        expect(validation['errors']).to include('Port must be between 1 and 65535')
      end

      it 'detects invalid protocol' do
        services = {
          invalid: { host: 'localhost', port: 3000, protocol: 'ftp' }
        }

        post '/api/v1/internal/reverse_proxy/validate_services',
             headers: internal_headers,
             params: { services: services },
             as: :json

        expect_success_response
        response_data = json_response

        validation = response_data['data']['data']['validations']['invalid']
        expect(validation['valid']).to be false
        expect(validation['errors']).to be_present
      end
    end
  end
end

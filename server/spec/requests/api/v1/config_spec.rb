# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Config', type: :request do
  describe 'GET /api/v1/config' do
    context 'without authentication' do
      it 'returns configuration data' do
        get '/api/v1/config', as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'api',
          'features',
          'version'
        )
      end

      it 'includes API configuration' do
        get '/api/v1/config', as: :json

        expect_success_response
        api_config = json_response['data']['api']

        expect(api_config).to include(
          'base_url',
          'websocket_url',
          'detected_proxy'
        )
      end

      it 'includes feature flags' do
        get '/api/v1/config', as: :json

        expect_success_response
        features = json_response['data']['features']

        expect(features).to include(
          'registration_enabled',
          'email_verification_required',
          'multi_tenancy_enabled'
        )
      end

      it 'includes version information' do
        get '/api/v1/config', as: :json

        expect_success_response
        version = json_response['data']['version']

        expect(version).to include('api', 'app')
        expect(version['api']).to eq('v1')
      end

      it 'generates correct API base URL' do
        get '/api/v1/config', as: :json

        expect_success_response
        api_url = json_response['data']['api']['base_url']

        expect(api_url).to include('/api/v1')
      end

      it 'generates correct WebSocket URL' do
        get '/api/v1/config', as: :json

        expect_success_response
        ws_url = json_response['data']['api']['websocket_url']

        expect(ws_url).to include('/cable')
      end
    end

    context 'with proxy headers' do
      it 'detects proxy and adjusts URLs' do
        get '/api/v1/config',
            headers: {
              'X-Forwarded-Host' => 'proxy.example.com',
              'X-Forwarded-Proto' => 'https'
            },
            as: :json

        expect_success_response
        expect(json_response['data']['api']['detected_proxy']).to be true
      end

      it 'uses proxy headers for API URL' do
        get '/api/v1/config',
            headers: {
              'X-Forwarded-Host' => 'proxy.example.com',
              'X-Forwarded-Proto' => 'https'
            },
            as: :json

        expect_success_response
        api_url = json_response['data']['api']['base_url']

        expect(api_url).to include('proxy.example.com')
        expect(api_url).to start_with('https://')
      end

      it 'uses proxy headers for WebSocket URL' do
        get '/api/v1/config',
            headers: {
              'X-Forwarded-Host' => 'proxy.example.com',
              'X-Forwarded-Proto' => 'https'
            },
            as: :json

        expect_success_response
        ws_url = json_response['data']['api']['websocket_url']

        expect(ws_url).to include('proxy.example.com')
        expect(ws_url).to start_with('wss://')
      end
    end
  end

  describe 'GET /api/v1/config/allowed_hosts' do
    context 'without authentication' do
      it 'returns allowed hosts' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        expect(json_response['data']).to include(
          'allowed_hosts',
          'source',
          'fetched_at'
        )
      end

      it 'includes localhost variants' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        hosts = json_response['data']['allowed_hosts']

        expect(hosts).to include('localhost', '127.0.0.1', '::1')
      end

      it 'removes duplicates' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        hosts = json_response['data']['allowed_hosts']

        expect(hosts.uniq.length).to eq(hosts.length)
      end

      it 'sorts hosts alphabetically' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        hosts = json_response['data']['allowed_hosts']

        expect(hosts).to eq(hosts.sort)
      end

      it 'includes source and timestamp' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        expect(json_response['data']['source']).to eq('backend')
        expect(json_response['data']['fetched_at']).to be_present
      end
    end

    context 'with admin settings' do
      before do
        AdminSetting.create!(key: 'trusted_hosts', value: ['example.com'])
        AdminSetting.create!(key: 'allowed_hosts', value: ['api.example.com'])
      end

      it 'includes hosts from admin settings' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_success_response
        hosts = json_response['data']['allowed_hosts']

        expect(hosts).to include('example.com', 'api.example.com')
      end
    end

    context 'with error handling' do
      before do
        allow(AdminSetting).to receive(:reverse_proxy_url_config).and_raise(StandardError.new('Config error'))
      end

      it 'returns error on failure' do
        get '/api/v1/config/allowed_hosts', as: :json

        expect_error_response('Failed to fetch configuration', 500)
      end
    end
  end
end

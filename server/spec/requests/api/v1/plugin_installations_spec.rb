# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::PluginInstallations', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  # Helper to create Plugin since factory may not exist
  let(:create_plugin) do
    ->(attrs = {}) {
      Plugin.create!({
        account: account,
        creator: user,
        plugin_id: "plugin-#{SecureRandom.hex(4)}",
        name: "Test Plugin #{SecureRandom.hex(4)}",
        description: 'A test plugin',
        version: '1.0.0',
        author: 'Test Author',
        status: 'active',
        plugin_types: ['ai_provider'],
        capabilities: ['text_generation'],
        manifest: { entry_point: 'index.js' },
        configuration: {}
      }.merge(attrs))
    }
  end

  # Helper to create PluginInstallation
  let(:create_installation) do
    ->(plugin, attrs = {}) {
      PluginInstallation.create!({
        account: account,
        plugin: plugin,
        installed_by: user,
        status: 'active',
        installed_at: Time.current,
        configuration: {}
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/plugin_installations' do
    let(:plugin) { create_plugin.call }

    before do
      3.times { create_installation.call(create_plugin.call) }
    end

    it 'returns list of installations' do
      get '/api/v1/plugin_installations', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['installations']).to be_an(Array)
      expect(response_data['data']['installations'].length).to eq(3)
    end

    it 'includes installation details' do
      get '/api/v1/plugin_installations', headers: headers, as: :json

      response_data = json_response
      first_installation = response_data['data']['installations'].first

      expect(first_installation).to include('id', 'status')
    end

    it 'includes plugin information' do
      get '/api/v1/plugin_installations', headers: headers, as: :json

      response_data = json_response
      first_installation = response_data['data']['installations'].first

      expect(first_installation).to have_key('plugin')
    end

    it 'filters by status' do
      plugin = create_plugin.call
      create_installation.call(plugin, status: 'inactive')

      get '/api/v1/plugin_installations',
          params: { status: 'inactive' },
          headers: headers,
          as: :json

      expect_success_response
      response_data = json_response

      statuses = response_data['data']['installations'].map { |i| i['status'] }
      expect(statuses.uniq).to eq(['inactive'])
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/plugin_installations', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/plugin_installations/:id' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin) }

    it 'returns installation details' do
      get "/api/v1/plugin_installations/#{installation.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['installation']).to include(
        'id' => installation.id,
        'status' => installation.status
      )
    end

    it 'includes plugin details' do
      get "/api/v1/plugin_installations/#{installation.id}", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['installation']).to have_key('plugin')
    end

    it 'includes installed_by user' do
      get "/api/v1/plugin_installations/#{installation.id}", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['installation']).to have_key('installed_by')
    end

    context 'when installation does not exist' do
      it 'returns not found error' do
        get '/api/v1/plugin_installations/nonexistent-id', headers: headers, as: :json

        expect_error_response('Installation not found', 404)
      end
    end

    context 'when accessing other account installation' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_plugin) do
        Plugin.create!(
          account: other_account,
          creator: other_user,
          plugin_id: 'other-plugin',
          name: 'Other Plugin',
          description: 'Other plugin',
          version: '1.0.0',
          status: 'active',
          plugin_types: ['workflow_node']
        )
      end
      let(:other_installation) do
        PluginInstallation.create!(
          account: other_account,
          plugin: other_plugin,
          installed_by: other_user,
          status: 'active',
          installed_at: Time.current
        )
      end

      it 'returns not found error' do
        get "/api/v1/plugin_installations/#{other_installation.id}", headers: headers, as: :json

        expect_error_response('Installation not found', 404)
      end
    end
  end

  describe 'PATCH /api/v1/plugin_installations/:id' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin) }

    it 'updates installation successfully' do
      patch "/api/v1/plugin_installations/#{installation.id}",
            params: { installation: { configuration: { api_key: 'updated-key' } } },
            headers: headers,
            as: :json

      expect_success_response

      installation.reload
      expect(installation.configuration['api_key']).to eq('updated-key')
    end
  end

  describe 'POST /api/v1/plugin_installations/:id/activate' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin, status: 'inactive') }

    it 'activates installation' do
      allow_any_instance_of(PluginInstallation).to receive(:activate!).and_return(true)

      post "/api/v1/plugin_installations/#{installation.id}/activate", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['message']).to include('activated successfully')
    end
  end

  describe 'POST /api/v1/plugin_installations/:id/deactivate' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin, status: 'active') }

    it 'deactivates installation' do
      allow_any_instance_of(PluginInstallation).to receive(:deactivate!).and_return(true)

      post "/api/v1/plugin_installations/#{installation.id}/deactivate", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['message']).to include('deactivated successfully')
    end
  end

  describe 'PATCH /api/v1/plugin_installations/:id/configure' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin) }

    it 'updates configuration' do
      allow_any_instance_of(PluginInstallationService).to receive(:update_plugin_configuration).and_return(true)

      patch "/api/v1/plugin_installations/#{installation.id}/configure",
            params: { configuration: { api_key: 'new-key', timeout: 30 } },
            headers: headers,
            as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['message']).to include('configuration updated')
    end
  end

  describe 'POST /api/v1/plugin_installations/:id/set_credential' do
    let(:plugin) { create_plugin.call }
    let(:installation) { create_installation.call(plugin) }

    it 'sets credential' do
      allow_any_instance_of(PluginInstallation).to receive(:set_credential).and_return(true)

      post "/api/v1/plugin_installations/#{installation.id}/set_credential",
           params: { credential_key: 'api_key', credential_value: 'secret-123' },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['message']).to include('Credential set successfully')
    end

    it 'requires credential key' do
      post "/api/v1/plugin_installations/#{installation.id}/set_credential",
           params: { credential_value: 'secret-123' },
           headers: headers,
           as: :json

      expect_error_response('Credential key and value are required', 422)
    end

    it 'requires credential value' do
      post "/api/v1/plugin_installations/#{installation.id}/set_credential",
           params: { credential_key: 'api_key' },
           headers: headers,
           as: :json

      expect_error_response('Credential key and value are required', 422)
    end
  end
end

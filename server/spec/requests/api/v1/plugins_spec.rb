# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Plugins', type: :request do
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

  describe 'GET /api/v1/plugins' do
    before do
      3.times { create_plugin.call }
    end

    it 'returns list of plugins' do
      get '/api/v1/plugins', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['plugins']).to be_an(Array)
      expect(response_data['data']['plugins'].length).to eq(3)
    end

    it 'includes plugin details' do
      get '/api/v1/plugins', headers: headers, as: :json

      response_data = json_response
      first_plugin = response_data['data']['plugins'].first

      expect(first_plugin).to include('id', 'name', 'version', 'status')
    end

    it 'filters by status' do
      create_plugin.call(status: 'inactive')

      get '/api/v1/plugins',
          params: { status: 'inactive' },
          headers: headers,
          as: :json

      expect_success_response
      response_data = json_response

      statuses = response_data['data']['plugins'].map { |p| p['status'] }
      expect(statuses.uniq).to eq(['inactive'])
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/plugins', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/plugins/:id' do
    let(:plugin) { create_plugin.call }

    it 'returns plugin details' do
      get "/api/v1/plugins/#{plugin.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['plugin']).to include(
        'id' => plugin.id,
        'name' => plugin.name
      )
    end

    it 'includes installation status' do
      get "/api/v1/plugins/#{plugin.id}", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']).to have_key('is_installed')
    end

    context 'when plugin does not exist' do
      it 'returns not found error' do
        get '/api/v1/plugins/nonexistent-id', headers: headers, as: :json

        expect_error_response('Plugin not found', 404)
      end
    end
  end

  describe 'POST /api/v1/plugins' do
    let(:valid_params) do
      {
        plugin: {
          plugin_id: 'new-plugin-123',
          name: 'New Test Plugin',
          description: 'A new test plugin',
          version: '1.0.0',
          author: 'Test Author',
          plugin_types: ['workflow_node'],
          capabilities: ['data_transformation']
        }
      }
    end

    it 'creates a new plugin' do
      expect {
        post '/api/v1/plugins', params: valid_params, headers: headers, as: :json
      }.to change(Plugin, :count).by(1)

      expect_success_response
      response_data = json_response

      expect(response_data['data']['plugin']['name']).to eq('New Test Plugin')
    end

    it 'sets current user as creator' do
      post '/api/v1/plugins', params: valid_params, headers: headers, as: :json

      response_data = json_response
      plugin = Plugin.find(response_data['data']['plugin']['id'])
      expect(plugin.creator_id).to eq(user.id)
    end
  end

  describe 'PATCH /api/v1/plugins/:id' do
    let(:plugin) { create_plugin.call }

    it 'updates plugin successfully' do
      patch "/api/v1/plugins/#{plugin.id}",
            params: { plugin: { description: 'Updated description' } },
            headers: headers,
            as: :json

      expect_success_response

      plugin.reload
      expect(plugin.description).to eq('Updated description')
    end
  end

  describe 'DELETE /api/v1/plugins/:id' do
    let(:plugin) { create_plugin.call }

    it 'deletes plugin successfully' do
      plugin_id = plugin.id

      delete "/api/v1/plugins/#{plugin_id}", headers: headers, as: :json

      expect_success_response
      expect(Plugin.find_by(id: plugin_id)).to be_nil
    end
  end

  describe 'POST /api/v1/plugins/:id/install' do
    let(:plugin) { create_plugin.call }

    it 'installs plugin' do
      installation = double(
        id: 'installation-123',
        as_json: { id: 'installation-123', status: 'active' }
      )

      allow_any_instance_of(PluginInstallationService).to receive(:install_plugin).and_return(installation)

      post "/api/v1/plugins/#{plugin.id}/install",
           params: { configuration: { api_key: 'test' } },
           headers: headers,
           as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['message']).to include('installed successfully')
    end
  end

  describe 'DELETE /api/v1/plugins/:id/uninstall' do
    let(:plugin) { create_plugin.call }

    context 'when plugin is installed' do
      it 'uninstalls plugin' do
        installation = double(status: 'active')
        allow_any_instance_of(Plugin).to receive(:installation_for).and_return(installation)
        allow_any_instance_of(PluginInstallationService).to receive(:uninstall_plugin).and_return(true)

        delete "/api/v1/plugins/#{plugin.id}/uninstall", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('uninstalled successfully')
      end
    end

    context 'when plugin is not installed' do
      it 'returns error' do
        allow_any_instance_of(Plugin).to receive(:installation_for).and_return(nil)

        delete "/api/v1/plugins/#{plugin.id}/uninstall", headers: headers, as: :json

        expect_error_response('Plugin is not installed', 422)
      end
    end
  end

  describe 'GET /api/v1/plugins/search' do
    before do
      create_plugin.call(name: 'Unique Search Plugin')
    end

    it 'searches plugins by query' do
      allow(Plugin).to receive(:search_by_text).and_return(Plugin.where("name ILIKE ?", "%Unique%"))

      get '/api/v1/plugins/search',
          params: { q: 'Unique' },
          headers: headers,
          as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['plugins']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/plugins/by_capability' do
    before do
      create_plugin.call(capabilities: ['text_generation'])
      create_plugin.call(capabilities: ['image_generation'])
    end

    it 'returns plugins by capability' do
      allow(Plugin).to receive(:with_capability).and_return(Plugin.where("'text_generation' = ANY(capabilities)"))

      get '/api/v1/plugins/by_capability',
          params: { capability: 'text_generation' },
          headers: headers,
          as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['plugins']).to be_an(Array)
    end
  end
end

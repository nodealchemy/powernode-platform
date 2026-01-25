# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::PluginMarketplaces', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  # Helper to create PluginMarketplace since factory may not exist
  let(:create_marketplace) do
    ->(attrs = {}) {
      PluginMarketplace.create!({
        account: account,
        creator: user,
        name: "Test Marketplace #{SecureRandom.hex(4)}",
        owner: 'test-owner',
        description: 'A test plugin marketplace',
        marketplace_type: 'github',
        source_type: 'repository',
        source_url: 'https://github.com/test/plugins',
        visibility: 'private',
        configuration: {}
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/plugin_marketplaces' do
    before do
      3.times { create_marketplace.call }
    end

    it 'returns list of marketplaces' do
      get '/api/v1/plugin_marketplaces', headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['marketplaces']).to be_an(Array)
      expect(response_data['data']['marketplaces'].length).to eq(3)
    end

    it 'includes marketplace details' do
      get '/api/v1/plugin_marketplaces', headers: headers, as: :json

      response_data = json_response
      first_marketplace = response_data['data']['marketplaces'].first

      expect(first_marketplace).to include('id', 'name', 'owner', 'marketplace_type')
    end

    it 'includes creator information' do
      get '/api/v1/plugin_marketplaces', headers: headers, as: :json

      response_data = json_response
      first_marketplace = response_data['data']['marketplaces'].first

      expect(first_marketplace).to have_key('creator')
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/plugin_marketplaces', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/plugin_marketplaces/:id' do
    let(:marketplace) { create_marketplace.call }

    it 'returns marketplace details' do
      get "/api/v1/plugin_marketplaces/#{marketplace.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['marketplace']).to include(
        'id' => marketplace.id,
        'name' => marketplace.name,
        'owner' => marketplace.owner
      )
    end

    it 'includes creator details' do
      get "/api/v1/plugin_marketplaces/#{marketplace.id}", headers: headers, as: :json

      response_data = json_response
      expect(response_data['data']['marketplace']).to have_key('creator')
    end

    context 'when marketplace does not exist' do
      it 'returns not found error' do
        get '/api/v1/plugin_marketplaces/nonexistent-id', headers: headers, as: :json

        expect_error_response('Marketplace not found', 404)
      end
    end

    context 'when accessing other account marketplace' do
      let(:other_account) { create(:account) }
      let(:other_user) { create(:user, account: other_account) }
      let(:other_marketplace) do
        PluginMarketplace.create!(
          account: other_account,
          creator: other_user,
          name: 'Other Marketplace',
          owner: 'other-owner',
          marketplace_type: 'github',
          source_type: 'repository',
          source_url: 'https://github.com/other/plugins',
          visibility: 'private'
        )
      end

      it 'returns not found error' do
        get "/api/v1/plugin_marketplaces/#{other_marketplace.id}", headers: headers, as: :json

        expect_error_response('Marketplace not found', 404)
      end
    end
  end

  describe 'POST /api/v1/plugin_marketplaces' do
    let(:valid_params) do
      {
        marketplace: {
          name: 'New Test Marketplace',
          owner: 'new-owner',
          description: 'A new test marketplace',
          marketplace_type: 'github',
          source_type: 'repository',
          source_url: 'https://github.com/new/plugins',
          visibility: 'private'
        }
      }
    end

    it 'creates a new marketplace' do
      expect {
        post '/api/v1/plugin_marketplaces', params: valid_params, headers: headers, as: :json
      }.to change(PluginMarketplace, :count).by(1)

      expect_success_response
      response_data = json_response

      expect(response_data['data']['marketplace']['name']).to eq('New Test Marketplace')
    end

    it 'sets current user as creator' do
      post '/api/v1/plugin_marketplaces', params: valid_params, headers: headers, as: :json

      response_data = json_response
      marketplace = PluginMarketplace.find(response_data['data']['marketplace']['id'])
      expect(marketplace.creator_id).to eq(user.id)
    end
  end

  describe 'PATCH /api/v1/plugin_marketplaces/:id' do
    let(:marketplace) { create_marketplace.call }

    it 'updates marketplace successfully' do
      patch "/api/v1/plugin_marketplaces/#{marketplace.id}",
            params: { marketplace: { description: 'Updated description' } },
            headers: headers,
            as: :json

      expect_success_response

      marketplace.reload
      expect(marketplace.description).to eq('Updated description')
    end

    it 'updates marketplace name' do
      patch "/api/v1/plugin_marketplaces/#{marketplace.id}",
            params: { marketplace: { name: 'Updated Name' } },
            headers: headers,
            as: :json

      expect_success_response

      marketplace.reload
      expect(marketplace.name).to eq('Updated Name')
    end
  end

  describe 'DELETE /api/v1/plugin_marketplaces/:id' do
    let(:marketplace) { create_marketplace.call }

    it 'deletes marketplace successfully' do
      marketplace_id = marketplace.id

      delete "/api/v1/plugin_marketplaces/#{marketplace_id}", headers: headers, as: :json

      expect_success_response
      expect(PluginMarketplace.find_by(id: marketplace_id)).to be_nil
    end
  end

  describe 'POST /api/v1/plugin_marketplaces/:id/sync' do
    let(:marketplace) { create_marketplace.call }

    it 'syncs marketplace plugins' do
      allow_any_instance_of(PluginMarketplaceSyncService).to receive(:sync).and_return(
        { synced_count: 5, new_count: 3, updated_count: 2 }
      )

      post "/api/v1/plugin_marketplaces/#{marketplace.id}/sync", headers: headers, as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to include('synced_plugins', 'new_plugins', 'updated_plugins')
      expect(response_data['data']['message']).to include('Synced')
    end
  end
end

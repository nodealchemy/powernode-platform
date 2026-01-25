# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::StorageProviders', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  before do
    # Grant required permissions
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
  end

  describe 'GET /api/v1/storage_providers' do
    let!(:storage1) { create(:file_storage, account: account, is_default: true) }
    let!(:storage2) { create(:file_storage, account: account) }

    context 'with proper permissions' do
      it 'returns list of storage providers' do
        get '/api/v1/storage_providers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['storages']).to be_an(Array)
        expect(data['total_count']).to eq(2)
        expect(data['default_storage']).to be_present
      end
    end

    context 'without permissions' do
      before do
        allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
      end

      it 'returns forbidden error' do
        get '/api/v1/storage_providers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/storage_providers/:id' do
    let(:storage) { create(:file_storage, account: account) }

    context 'with proper permissions' do
      it 'returns storage provider details' do
        get "/api/v1/storage_providers/#{storage.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['storage']).to be_present
        expect(data['storage']['id']).to eq(storage.id)
      end
    end

    context 'when storage not found' do
      it 'returns not found error' do
        get "/api/v1/storage_providers/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Storage configuration not found', 404)
      end
    end
  end

  describe 'POST /api/v1/storage_providers' do
    let(:valid_params) do
      {
        name: 'Test Storage',
        provider_type: 'local',
        description: 'Test storage provider',
        configuration: { path: '/tmp/storage' }
      }
    end

    context 'with valid params' do
      it 'creates a new storage provider' do
        expect {
          post '/api/v1/storage_providers', params: valid_params, headers: headers, as: :json
        }.to change { account.file_storages.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['message']).to eq('Storage configuration created successfully')
      end

      it 'initializes storage if requested' do
        allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :initialize_storage)

        post '/api/v1/storage_providers', params: valid_params.merge(initialize: true), headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        invalid_params = valid_params.merge(name: nil)

        post '/api/v1/storage_providers', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /api/v1/storage_providers/:id' do
    let(:storage) { create(:file_storage, account: account) }
    let(:update_params) do
      {
        name: 'Updated Storage',
        description: 'Updated description'
      }
    end

    context 'with valid params' do
      it 'updates the storage provider' do
        patch "/api/v1/storage_providers/#{storage.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['storage']['name']).to eq('Updated Storage')
        expect(data['message']).to eq('Storage configuration updated successfully')
      end
    end
  end

  describe 'DELETE /api/v1/storage_providers/:id' do
    let!(:storage) { create(:file_storage, account: account) }

    context 'when storage can be deleted' do
      it 'deletes the storage provider' do
        allow_any_instance_of(FileStorage).to receive(:files_count).and_return(0)

        expect {
          delete "/api/v1/storage_providers/#{storage.id}", headers: headers, as: :json
        }.to change { account.file_storages.count }.by(-1)

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Storage configuration deleted successfully')
      end
    end

    context 'when storage is default' do
      let!(:default_storage) { create(:file_storage, account: account, is_default: true) }

      it 'returns error' do
        delete "/api/v1/storage_providers/#{default_storage.id}", headers: headers, as: :json

        expect_error_response('Cannot delete default storage configuration', 422)
      end
    end

    context 'when storage has existing files' do
      it 'returns error' do
        allow_any_instance_of(FileStorage).to receive(:files_count).and_return(5)

        delete "/api/v1/storage_providers/#{storage.id}", headers: headers, as: :json

        expect_error_response('Cannot delete storage with existing files. Move files to another storage first.', 422)
      end
    end
  end

  describe 'POST /api/v1/storage_providers/:id/test' do
    let(:storage) { create(:file_storage, account: account) }

    context 'when connection succeeds' do
      it 'returns success response' do
        allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :test_connection).and_return({
          success: true,
          message: 'Connection successful'
        })

        post "/api/v1/storage_providers/#{storage.id}/test", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['connected']).to be true
        expect(data['message']).to eq('Storage connection successful')
      end
    end

    context 'when connection fails' do
      it 'returns error response' do
        allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :test_connection).and_return({
          success: false,
          error: 'Connection failed'
        })

        post "/api/v1/storage_providers/#{storage.id}/test", headers: headers, as: :json

        expect_error_response('Connection test failed: Connection failed', 422)
      end
    end
  end

  describe 'GET /api/v1/storage_providers/:id/health' do
    let(:storage) { create(:file_storage, account: account) }

    it 'returns health check status' do
      allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :health_check).and_return({
        status: 'healthy',
        details: { available: true }
      })

      get "/api/v1/storage_providers/#{storage.id}/health", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['status']).to eq('healthy')
      expect(data['storage_id']).to eq(storage.id)
    end
  end

  describe 'POST /api/v1/storage_providers/:id/set_default' do
    let!(:storage) { create(:file_storage, account: account) }
    let!(:default_storage) { create(:file_storage, account: account, is_default: true) }

    it 'sets storage as default' do
      post "/api/v1/storage_providers/#{storage.id}/set_default", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('Default storage updated successfully')
      expect(storage.reload.is_default).to be true
      expect(default_storage.reload.is_default).to be false
    end
  end

  describe 'GET /api/v1/storage_providers/supported' do
    it 'returns list of supported providers' do
      allow(StorageProviderFactory).to receive(:supported_providers).and_return(['local', 's3'])
      allow(StorageProviderFactory).to receive(:provider_capabilities).and_return({ versioning: true })
      allow(StorageProviderFactory).to receive(:check_dependencies).and_return({
        available: true,
        missing: []
      })

      get '/api/v1/storage_providers/supported', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['providers']).to be_an(Array)
      expect(data['total_count']).to eq(2)
    end
  end

  describe 'POST /api/v1/storage_providers/:id/initialize' do
    let(:storage) { create(:file_storage, account: account) }

    it 'initializes storage backend' do
      allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :initialize_storage).and_return(true)

      post "/api/v1/storage_providers/#{storage.id}/initialize", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['initialized']).to be true
      expect(data['message']).to eq('Storage backend initialized successfully')
    end
  end

  describe 'GET /api/v1/storage_providers/:id/files' do
    let(:storage) { create(:file_storage, account: account) }

    it 'lists files in storage' do
      files = [
        { key: 'file1.txt', size: 100 },
        { key: 'file2.txt', size: 200 }
      ]
      allow_any_instance_of(FileStorage).to receive_message_chain(:storage_provider, :list_files).and_return(files)

      get "/api/v1/storage_providers/#{storage.id}/files", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['files']).to be_an(Array)
      expect(data['count']).to eq(2)
    end
  end

  describe 'GET /api/v1/storage_providers/stats' do
    let!(:storage1) { create(:file_storage, account: account) }
    let!(:storage2) { create(:file_storage, account: account) }

    it 'returns aggregate storage statistics' do
      allow_any_instance_of(FileStorage).to receive(:files_count).and_return(10)
      allow_any_instance_of(FileStorage).to receive(:total_size_bytes).and_return(1024)
      allow_any_instance_of(FileStorage).to receive(:quota_bytes).and_return(10240)
      allow_any_instance_of(FileStorage).to receive(:quota_enabled?).and_return(true)

      get '/api/v1/storage_providers/stats', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('total_files')
      expect(data).to have_key('total_size_bytes')
      expect(data).to have_key('providers')
      expect(data['storages_count']).to eq(2)
    end
  end
end

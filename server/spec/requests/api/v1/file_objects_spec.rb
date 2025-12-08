# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::FileObjects', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['files.upload', 'files.read', 'files.delete', 'files.manage']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['files.read']) }
  let(:storage) do
    FileStorage.create!(
      account: account,
      name: 'API Test Storage',
      provider_type: 'local',
      configuration: {
        'root_path' => Rails.root.join('tmp', 'api_test_storage', account.id).to_s
      },
      is_default: true,
      status: 'active',
      quota_bytes: 100.megabytes
    )
  end

  let(:headers) do
    token = JwtService.generate_user_tokens(user)[:access_token]
    { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
  end

  let(:read_only_headers) do
    token = JwtService.generate_user_tokens(read_only_user)[:access_token]
    { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }
  end

  before do
    FileUtils.mkdir_p(storage.configuration['root_path'])
  end

  after do
    FileUtils.rm_rf(Rails.root.join('tmp', 'api_test_storage'))
  end

  describe 'POST /api/v1/file_objects' do
    let(:file_upload) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'files', 'test_document.txt'), 'text/plain') }

    before do
      # Create fixture file
      FileUtils.mkdir_p(Rails.root.join('spec', 'fixtures', 'files'))
      File.write(Rails.root.join('spec', 'fixtures', 'files', 'test_document.txt'), 'Test document content')
    end

    after do
      FileUtils.rm_rf(Rails.root.join('spec', 'fixtures', 'files'))
    end

    it 'uploads a file successfully' do
      post '/api/v1/file_objects',
           params: {
             file: file_upload,
             category: 'user_upload',
             visibility: 'private'
           },
           headers: headers.except('Content-Type')

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['filename']).to eq('test_document.txt')
      expect(json['data']['file_type']).to eq('document')
      expect(json['data']['category']).to eq('user_upload')
    end

    it 'rejects upload without required permission' do
      no_permission_user = create(:user, account: account, permissions: [])
      token = JwtService.generate_user_tokens(no_permission_user)[:access_token]
      headers_no_permission = { 'Authorization' => "Bearer #{token}" }

      post '/api/v1/file_objects',
           params: {
             file: file_upload,
             category: 'user_upload'
           },
           headers: headers_no_permission

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to include('permission')
    end

    it 'validates file size limits' do
      allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(6.gigabytes)

      post '/api/v1/file_objects',
           params: {
             file: file_upload,
             category: 'user_upload'
           },
           headers: headers.except('Content-Type')

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to include('size')
    end

    it 'enforces storage quota limits' do
      storage.update!(quota_bytes: 10.bytes, total_size_bytes: 5.bytes)

      post '/api/v1/file_objects',
           params: {
             file: file_upload,
             category: 'user_upload'
           },
           headers: headers.except('Content-Type')

      expect(response).to have_http_status(:unprocessable_content)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
      expect(json['error']).to include('quota')
    end
  end

  describe 'GET /api/v1/file_objects' do
    let!(:files) do
      3.times.map do |i|
        FileObject.create!(
          account: account,
          file_storage: storage,
          uploaded_by: user,
          filename: "test_file_#{i}.txt",
          storage_key: "test/file_#{i}.txt",
          content_type: 'text/plain',
          file_size: 100,
          file_type: 'document',
          category: i.even? ? 'user_upload' : 'workflow_output'
        )
      end
    end

    it 'lists all files for the account' do
      get '/api/v1/file_objects', headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data'].length).to eq(3)
    end

    it 'filters files by category' do
      get '/api/v1/file_objects', params: { category: 'user_upload' }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data'].length).to eq(2)
      expect(json['data'].all? { |f| f['category'] == 'user_upload' }).to be true
    end

    it 'filters files by file_type' do
      FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'test_image.jpg',
        storage_key: 'test/image.jpg',
        content_type: 'image/jpeg',
        file_size: 1000,
        file_type: 'image',
        category: 'user_upload'
      )

      get '/api/v1/file_objects', params: { file_type: 'image' }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data'].length).to eq(1)
      expect(json['data'].first['file_type']).to eq('image')
    end

    it 'paginates results' do
      get '/api/v1/file_objects', params: { page: 1, per_page: 2 }, headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data'].length).to eq(2)
      expect(json['pagination']).to be_present
      expect(json['pagination']['total_count']).to eq(3)
    end

    it 'requires authentication' do
      get '/api/v1/file_objects'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/file_objects/:id' do
    let(:file_object) do
      FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'test_detail.txt',
        storage_key: 'test/detail.txt',
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload'
      )
    end

    it 'returns file details' do
      get "/api/v1/file_objects/#{file_object.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(file_object.id)
      expect(json['data']['filename']).to eq('test_detail.txt')
    end

    it 'returns 404 for non-existent file' do
      get "/api/v1/file_objects/#{SecureRandom.uuid}", headers: headers

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end

    it 'prevents access to files from different account' do
      other_account = create(:account)
      other_user = create(:user, account: other_account, permissions: ['files.read'])
      other_token = JwtService.generate_user_tokens(other_user)[:access_token]
      other_headers = { 'Authorization' => "Bearer #{other_token}", 'Content-Type' => 'application/json' }

      get "/api/v1/file_objects/#{file_object.id}", headers: other_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/file_objects/:id/download' do
    let(:test_content) { 'This is test file content for download' }
    let(:file_object) do
      obj = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'download_test.txt',
        storage_key: "downloads/#{SecureRandom.uuid}/download_test.txt",
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      # Upload actual file
      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(obj, StringIO.new(test_content))

      obj
    end

    it 'provides download URL' do
      get "/api/v1/file_objects/#{file_object.id}/download", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['download_url']).to be_present
      expect(json['data']['expires_at']).to be_present
    end

    it 'increments download count' do
      expect {
        get "/api/v1/file_objects/#{file_object.id}/download", headers: headers
      }.to change { file_object.reload.download_count }.by(1)
    end

    it 'requires read permission' do
      no_permission_user = create(:user, account: account, permissions: [])
      token = JwtService.generate_user_tokens(no_permission_user)[:access_token]
      no_permission_headers = { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }

      get "/api/v1/file_objects/#{file_object.id}/download", headers: no_permission_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'DELETE /api/v1/file_objects/:id' do
    let(:test_content) { 'File to be deleted' }
    let(:file_object) do
      obj = FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'delete_test.txt',
        storage_key: "delete/#{SecureRandom.uuid}/delete_test.txt",
        content_type: 'text/plain',
        file_size: test_content.bytesize,
        file_type: 'document',
        category: 'user_upload'
      )

      # Upload actual file
      provider = StorageProviderFactory.get_provider(storage)
      provider.upload_file(obj, StringIO.new(test_content))

      obj
    end

    it 'soft deletes the file' do
      delete "/api/v1/file_objects/#{file_object.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      file_object.reload
      expect(file_object.deleted_at).to be_present
      expect(file_object.deleted_by_id).to eq(user.id)
    end

    it 'prevents deletion without permission' do
      delete "/api/v1/file_objects/#{file_object.id}", headers: read_only_headers

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end

    it 'returns 404 for already deleted file' do
      file_object.update!(deleted_at: Time.current, deleted_by: user)

      delete "/api/v1/file_objects/#{file_object.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/file_objects/:id/restore' do
    let(:deleted_file) do
      FileObject.create!(
        account: account,
        file_storage: storage,
        uploaded_by: user,
        filename: 'restore_test.txt',
        storage_key: 'restore/test.txt',
        content_type: 'text/plain',
        file_size: 100,
        file_type: 'document',
        category: 'user_upload',
        deleted_at: 1.day.ago,
        deleted_by: user
      )
    end

    it 'restores a soft-deleted file' do
      post "/api/v1/file_objects/#{deleted_file.id}/restore", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      deleted_file.reload
      expect(deleted_file.deleted_at).to be_nil
      expect(deleted_file.deleted_by_id).to be_nil
    end

    it 'requires manage permission to restore' do
      post "/api/v1/file_objects/#{deleted_file.id}/restore", headers: read_only_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end

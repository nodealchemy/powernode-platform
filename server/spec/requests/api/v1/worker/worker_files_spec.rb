# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Worker::WorkerFiles', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:worker) { create(:worker, account: account) }

  # Helper to create file object
  let(:create_file_object) do
    ->(attrs = {}) {
      FileManagement::Object.create!({
        account: account,
        user: user,
        filename: "test-file-#{SecureRandom.hex(4)}.jpg",
        content_type: 'image/jpeg',
        file_size: 1024,
        storage_key: "files/#{SecureRandom.uuid}",
        file_type: 'image',
        processing_status: 'pending',
        metadata: {},
        exif_data: {},
        dimensions: {}
      }.merge(attrs))
    }
  end

  # Worker authentication headers
  let(:worker_headers) do
    token = JWT.encode(
      { worker_id: worker.id, type: 'worker', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/worker/files/:id' do
    let(:file_object) { create_file_object.call }

    context 'with worker authentication' do
      it 'returns file object details' do
        get "/api/v1/worker/files/#{file_object.id}", headers: worker_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => file_object.id,
          'filename' => file_object.filename,
          'content_type' => file_object.content_type
        )
      end

      it 'includes file metadata' do
        get "/api/v1/worker/files/#{file_object.id}", headers: worker_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('metadata')
      end

      it 'includes processing status' do
        get "/api/v1/worker/files/#{file_object.id}", headers: worker_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('processing_status')
      end
    end

    context 'when file does not exist' do
      it 'returns not found error' do
        get '/api/v1/worker/files/nonexistent-id', headers: worker_headers, as: :json

        expect_error_response('File not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/worker/files/#{file_object.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/worker/files/:id/download' do
    let(:file_storage) { create(:file_storage, account: account) }
    let(:file_object) { create_file_object.call(file_storage: file_storage) }

    context 'with worker authentication' do
      it 'downloads file content' do
        allow_any_instance_of(FileStorageService).to receive(:download_file).and_return('file content')

        get "/api/v1/worker/files/#{file_object.id}/download", headers: worker_headers

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include(file_object.content_type)
      end

      it 'handles file not found in storage' do
        allow_any_instance_of(FileStorageService).to receive(:download_file)
          .and_raise(FileStorageService::FileNotFoundError.new('File not found'))

        get "/api/v1/worker/files/#{file_object.id}/download", headers: worker_headers, as: :json

        expect_error_response('File not found', 404)
      end
    end
  end

  describe 'PATCH /api/v1/worker/files/:id' do
    let(:file_object) { create_file_object.call }

    context 'with worker authentication' do
      it 'updates processing status' do
        patch "/api/v1/worker/files/#{file_object.id}",
              params: { processing_status: 'completed' },
              headers: worker_headers,
              as: :json

        expect_success_response

        file_object.reload
        expect(file_object.processing_status).to eq('completed')
      end

      it 'updates metadata' do
        patch "/api/v1/worker/files/#{file_object.id}",
              params: { metadata: { thumbnail_generated: true } },
              headers: worker_headers,
              as: :json

        expect_success_response

        file_object.reload
        expect(file_object.metadata['thumbnail_generated']).to eq(true)
      end

      it 'updates dimensions' do
        patch "/api/v1/worker/files/#{file_object.id}",
              params: { dimensions: { width: 800, height: 600 } },
              headers: worker_headers,
              as: :json

        expect_success_response

        file_object.reload
        expect(file_object.dimensions['width']).to eq(800)
      end

      it 'updates exif data' do
        patch "/api/v1/worker/files/#{file_object.id}",
              params: { exif_data: { camera: 'Canon EOS 5D' } },
              headers: worker_headers,
              as: :json

        expect_success_response

        file_object.reload
        expect(file_object.exif_data['camera']).to eq('Canon EOS 5D')
      end
    end
  end

  describe 'POST /api/v1/worker/files/:id/processed' do
    let(:file_storage) { create(:file_storage, account: account) }
    let(:file_object) { create_file_object.call(file_storage: file_storage) }

    context 'with worker authentication' do
      it 'uploads processed file' do
        allow_any_instance_of(Object).to receive(:upload_file_to_key).and_return(true)

        file_content = Base64.strict_encode64('thumbnail content')

        post "/api/v1/worker/files/#{file_object.id}/processed",
             params: {
               file_content: file_content,
               metadata: { type: 'thumbnail', size: 1024 }
             },
             headers: worker_headers,
             as: :json

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['message']).to include('uploaded successfully')
      end

      it 'requires file_content' do
        post "/api/v1/worker/files/#{file_object.id}/processed",
             params: { metadata: { type: 'thumbnail' } },
             headers: worker_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'rejects invalid base64' do
        post "/api/v1/worker/files/#{file_object.id}/processed",
             params: { file_content: 'not-valid-base64!' },
             headers: worker_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end

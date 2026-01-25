# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataManagement::ExportRequests', type: :request do
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:export_request) do
    create(:data_management_export_request,
           user: user,
           account: account,
           status: 'pending')
  end

  describe 'GET /api/v1/internal/data_export_requests/:id' do
    context 'with valid service token' do
      it 'returns export request details' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(export_request.id)
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
        expect(data).to include(
          'file_path',
          'file_url',
          'completed_at',
          'error_message',
          'created_at',
          'updated_at'
        )
      end
    end

    context 'with non-existent export request' do
      it 'returns not found error' do
        get '/api/v1/internal/data_export_requests/non-existent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Data export request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}",
            as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/data_export_requests' do
    context 'with valid service token' do
      let(:valid_params) do
        {
          user_id: user.id,
          account_id: account.id,
          status: 'pending'
        }
      end

      it 'creates a new export request' do
        expect do
          post '/api/v1/internal/data_export_requests',
               params: valid_params,
               headers: internal_headers,
               as: :json
        end.to change(DataManagement::ExportRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response

        data = json_response['data']
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
      end

      it 'creates export request with optional fields' do
        params = valid_params.merge(
          file_path: '/tmp/export.zip',
          file_url: 'https://storage.example.com/export.zip',
          metadata: { format: 'json' }
        )

        post '/api/v1/internal/data_export_requests',
             params: params,
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        post '/api/v1/internal/data_export_requests',
             params: { status: 'invalid' },
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/data_export_requests',
             params: { user_id: user.id, account_id: account.id },
             as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_export_requests/:id' do
    context 'with valid service token' do
      it 'updates export request status' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { status: 'processing' },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(export_request.id)
        expect(data['status']).to eq('processing')

        export_request.reload
        expect(export_request.status).to eq('processing')
      end

      it 'updates export request to completed with file details' do
        completed_at = Time.current
        file_path = '/exports/user_data.zip'
        file_url = 'https://storage.example.com/exports/user_data.zip'

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                status: 'completed',
                completed_at: completed_at,
                file_path: file_path,
                file_url: file_url
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.status).to eq('completed')
        expect(export_request.completed_at).to be_present
        expect(export_request.file_path).to eq(file_path)
        expect(export_request.file_url).to eq(file_url)
      end

      it 'updates export request with error' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                status: 'failed',
                error_message: 'Export generation failed'
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.status).to eq('failed')
        expect(export_request.error_message).to eq('Export generation failed')
      end

      it 'updates file_path independently' do
        new_path = '/new/path/export.zip'

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { file_path: new_path },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.file_path).to eq(new_path)
      end

      it 'updates file_url independently' do
        new_url = 'https://cdn.example.com/new_export.zip'

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { file_url: new_url },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.file_url).to eq(new_url)
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { status: 'invalid_status' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'with non-existent export request' do
      it 'returns not found error' do
        patch '/api/v1/internal/data_export_requests/non-existent-id',
              params: { status: 'completed' },
              headers: internal_headers,
              as: :json

        expect_error_response('Data export request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { status: 'completed' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'export request lifecycle' do
    it 'completes full lifecycle from pending to completed' do
      request = create(:data_management_export_request,
                       user: user,
                       account: account,
                       status: 'pending')

      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: { status: 'processing' },
            headers: internal_headers,
            as: :json
      expect_success_response

      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: {
              status: 'completed',
              completed_at: Time.current,
              file_path: '/exports/data.zip',
              file_url: 'https://storage.example.com/data.zip'
            },
            headers: internal_headers,
            as: :json
      expect_success_response

      request.reload
      expect(request.status).to eq('completed')
      expect(request.completed_at).to be_present
      expect(request.file_path).to be_present
      expect(request.file_url).to be_present
    end

    it 'handles failure during processing' do
      request = create(:data_management_export_request,
                       user: user,
                       account: account,
                       status: 'processing')

      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: {
              status: 'failed',
              error_message: 'Disk space insufficient'
            },
            headers: internal_headers,
            as: :json

      expect_success_response
      request.reload
      expect(request.status).to eq('failed')
      expect(request.error_message).to be_present
    end
  end
end

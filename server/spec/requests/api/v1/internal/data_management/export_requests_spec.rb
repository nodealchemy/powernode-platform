# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataExportRequests', type: :request do
  # Fix Ruby constant resolution: inside Api::V1::Internal, DataManagement::ExportRequest
  # resolves to Api::V1::Internal::DataManagement::ExportRequest (nonexistent) rather than
  # ::DataManagement::ExportRequest. Define the alias so the controller can find it.
  before(:all) do
    unless Api::V1::Internal::DataManagement.const_defined?(:ExportRequest, false)
      Api::V1::Internal::DataManagement.const_set(:ExportRequest, ::DataManagement::ExportRequest)
    end

    # Define stub job classes that the controller references but don't exist.
    # Must be defined both at top-level DataManagement:: and within
    # Api::V1::Internal::DataManagement:: since the controller's namespace resolution
    # will find the latter first.
    stub_job = Class.new(ApplicationJob) { def perform(*args); end }

    unless defined?(::DataManagement::ExportProcessingJob)
      ::DataManagement.const_set(:ExportProcessingJob, stub_job)
    end
    unless Api::V1::Internal::DataManagement.const_defined?(:ExportProcessingJob, false)
      Api::V1::Internal::DataManagement.const_set(:ExportProcessingJob, ::DataManagement::ExportProcessingJob)
    end

    unless defined?(::DataManagement::ExportExecutionJob)
      ::DataManagement.const_set(:ExportExecutionJob, stub_job)
    end
    unless Api::V1::Internal::DataManagement.const_defined?(:ExportExecutionJob, false)
      Api::V1::Internal::DataManagement.const_set(:ExportExecutionJob, ::DataManagement::ExportExecutionJob)
    end
  end

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

  before do
    # Stub NotificationService.send_email which the controller calls
    allow(NotificationService).to receive(:send_email).and_return(true)
  end

  describe 'GET /api/v1/internal/data_export_requests/:id' do
    context 'with valid service token' do
      it 'returns export request details' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']['data_export_request']

        expect(data['id']).to eq(export_request.id)
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
        # include_details: true adds these fields
        expect(data).to include(
          'file_path',
          'completed_at',
          'error_message',
          'created_at'
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
          data_export_request: {
            user_id: user.id,
            account_id: account.id,
            format: 'json',
            export_type: 'full'
          }
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

        data = json_response['data']['data_export_request']
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
      end

      it 'creates export request with metadata' do
        params = {
          data_export_request: {
            user_id: user.id,
            account_id: account.id,
            format: 'json',
            export_type: 'full',
            metadata: { source: 'api' }
          }
        }

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
             params: { data_export_request: { account_id: account.id } },
             headers: internal_headers,
             as: :json

        # Model validation fails (missing user, format, etc.) -> 422
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/data_export_requests',
             params: { data_export_request: { user_id: user.id, account_id: account.id } },
             as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_export_requests/:id' do
    context 'start action' do
      it 'starts a pending export request' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']['data_export_request']
        expect(data['id']).to eq(export_request.id)
        expect(data['status']).to eq('processing')

        export_request.reload
        expect(export_request.status).to eq('processing')
        expect(export_request.processing_started_at).to be_present
      end

      it 'rejects start of non-pending request' do
        export_request.update!(status: 'processing', processing_started_at: Time.current)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'complete action' do
      before do
        export_request.update!(status: 'processing', processing_started_at: Time.current)
      end

      it 'completes a processing export with file details' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                action_type: 'complete',
                file_path: '/exports/user_data.zip',
                file_size_bytes: 1024
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.status).to eq('completed')
        expect(export_request.completed_at).to be_present
        expect(export_request.file_path).to eq('/exports/user_data.zip')
      end

      it 'rejects completion of non-processing request' do
        export_request.update!(status: 'pending', processing_started_at: nil)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'fail action' do
      before do
        export_request.update!(status: 'processing', processing_started_at: Time.current)
      end

      it 'marks a processing export as failed' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                action_type: 'fail',
                error_message: 'Export generation failed'
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.status).to eq('failed')
        expect(export_request.error_message).to eq('Export generation failed')
      end

      it 'rejects failure of non-processing request' do
        export_request.update!(status: 'pending', processing_started_at: nil)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'fail', error_message: 'Error' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'expire action' do
      before do
        export_request.update!(
          status: 'completed',
          processing_started_at: 1.day.ago,
          completed_at: 23.hours.ago,
          file_path: '/tmp/nonexistent_export.zip',
          download_token: SecureRandom.urlsafe_base64(32),
          download_token_expires_at: 6.days.from_now,
          expires_at: 29.days.from_now
        )
      end

      it 'expires a completed export' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'expire' },
              headers: internal_headers,
              as: :json

        expect_success_response
        export_request.reload
        expect(export_request.status).to eq('expired')
        expect(export_request.download_token).to be_nil
      end

      it 'rejects expiration of non-completed request' do
        export_request.update!(status: 'pending', completed_at: nil, processing_started_at: nil,
                               file_path: nil, download_token: nil, download_token_expires_at: nil,
                               expires_at: nil)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'expire' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'generic update (no action_type)' do
      it 'updates metadata on the request' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { data_export_request: { metadata: { note: 'updated' } } },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']['data_export_request']
        expect(data['id']).to eq(export_request.id)
      end
    end

    context 'with non-existent export request' do
      it 'returns not found error' do
        patch '/api/v1/internal/data_export_requests/non-existent-id',
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect_error_response('Data export request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
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

      # Step 1: Start processing
      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: { action_type: 'start' },
            headers: internal_headers,
            as: :json
      expect_success_response
      request.reload
      expect(request.status).to eq('processing')

      # Step 2: Complete with file details
      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: {
              action_type: 'complete',
              file_path: '/exports/data.zip',
              file_size_bytes: 2048
            },
            headers: internal_headers,
            as: :json
      expect_success_response

      request.reload
      expect(request.status).to eq('completed')
      expect(request.completed_at).to be_present
      expect(request.file_path).to be_present
    end

    it 'handles failure during processing' do
      request = create(:data_management_export_request,
                       user: user,
                       account: account,
                       status: 'processing',
                       processing_started_at: Time.current)

      patch "/api/v1/internal/data_export_requests/#{request.id}",
            params: {
              action_type: 'fail',
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

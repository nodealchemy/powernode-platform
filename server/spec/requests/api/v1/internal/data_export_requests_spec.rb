# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataExportRequests', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  # Helper to create export request
  let(:create_export_request) do
    ->(attrs = {}) {
      DataManagement::ExportRequest.create!({
        account: account,
        user: user,
        request_id: SecureRandom.uuid,
        export_format: 'json',
        requester_email: user.email,
        requester_name: user.name,
        data_categories: ['profile', 'activity'],
        status: 'pending',
        requested_at: Time.current
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/data_export_requests/:id' do
    let(:export_request) { create_export_request.call }

    context 'with internal authentication' do
      it 'returns export request details' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data_export_request']).to include(
          'id' => export_request.id,
          'status' => 'pending'
        )
      end

      it 'includes detailed fields' do
        get "/api/v1/internal/data_export_requests/#{export_request.id}", headers: internal_headers, as: :json

        response_data = json_response
        expect(response_data['data']['data_export_request']).to have_key('data_categories')
      end
    end

    context 'when request does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/data_export_requests/nonexistent-id', headers: internal_headers, as: :json

        expect_error_response('Data export request not found', 404)
      end
    end
  end

  describe 'POST /api/v1/internal/data_export_requests' do
    let(:valid_params) do
      {
        data_export_request: {
          account_id: account.id,
          user_id: user.id,
          export_format: 'json',
          requester_email: user.email,
          requester_name: user.name,
          data_categories: ['profile', 'activity', 'audit_logs']
        }
      }
    end

    context 'with internal authentication' do
      it 'creates a new export request' do
        allow(DataManagement::ExportProcessingJob).to receive(:perform_later).and_return(true)

        expect {
          post '/api/v1/internal/data_export_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::ExportRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['data_export_request']['status']).to eq('pending')
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_export_requests/:id' do
    let(:export_request) { create_export_request.call(status: 'pending') }

    context 'with action_type: start' do
      it 'starts export processing' do
        allow(DataManagement::ExportExecutionJob).to receive(:perform_later).and_return(true)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('processing')
      end

      it 'rejects non-pending request' do
        export_request.update!(status: 'processing')

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'start' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with action_type: complete' do
      before { export_request.update!(status: 'processing', started_at: Time.current) }

      it 'completes export' do
        allow(NotificationService).to receive(:send_email).and_return(true)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: {
                action_type: 'complete',
                file_path: '/exports/export-123.zip',
                file_size_bytes: 1024000,
                download_url: 'https://example.com/download/123',
                record_count: 500
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('completed')
      end

      it 'rejects non-processing request' do
        export_request.update!(status: 'pending')

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with action_type: fail' do
      before { export_request.update!(status: 'processing', started_at: Time.current) }

      it 'marks export as failed' do
        allow(NotificationService).to receive(:send_email).and_return(true)

        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'fail', error_message: 'Export processing failed' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('failed')
      end
    end

    context 'with action_type: expire' do
      before do
        export_request.update!(
          status: 'completed',
          completed_at: Time.current,
          file_path: '/tmp/test-export.zip'
        )
      end

      it 'expires export' do
        patch "/api/v1/internal/data_export_requests/#{export_request.id}",
              params: { action_type: 'expire' },
              headers: internal_headers,
              as: :json

        expect_success_response

        export_request.reload
        expect(export_request.status).to eq('expired')
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataDeletionRequests', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, account: account, permissions: ['admin.data.manage']) }

  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  # Helper to create deletion request
  let(:create_deletion_request) do
    ->(attrs = {}) {
      DataManagement::DeletionRequest.create!({
        account: account,
        user: user,
        request_id: SecureRandom.uuid,
        request_type: 'user_data',
        reason: 'User requested account deletion',
        requester_email: user.email,
        requester_name: user.name,
        data_categories: ['profile', 'activity', 'files'],
        status: 'pending',
        requested_at: Time.current
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call }

    context 'with internal authentication' do
      it 'returns deletion request details' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data_deletion_request']).to include(
          'id' => deletion_request.id,
          'request_type' => 'user_data',
          'status' => 'pending'
        )
      end

      it 'includes detailed fields' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        response_data = json_response
        expect(response_data['data']['data_deletion_request']).to have_key('data_categories')
        expect(response_data['data']['data_deletion_request']).to have_key('reason')
      end
    end

    context 'when request does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/data_deletion_requests/nonexistent-id', headers: internal_headers, as: :json

        expect_error_response('Data deletion request not found', 404)
      end
    end
  end

  describe 'POST /api/v1/internal/data_deletion_requests' do
    let(:valid_params) do
      {
        data_deletion_request: {
          account_id: account.id,
          user_id: user.id,
          request_type: 'user_data',
          reason: 'GDPR deletion request',
          requester_email: user.email,
          requester_name: user.name,
          data_categories: ['profile', 'activity', 'audit_logs']
        }
      }
    end

    context 'with internal authentication' do
      it 'creates a new deletion request' do
        allow(DataManagement::DeletionProcessingJob).to receive(:perform_later).and_return(true)

        expect {
          post '/api/v1/internal/data_deletion_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::DeletionRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['data_deletion_request']['status']).to eq('pending')
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call(status: 'pending') }

    context 'with action_type: approve' do
      it 'approves deletion request' do
        allow(NotificationService).to receive(:send_email).and_return(true)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve', approved_by_id: admin_user.id },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('approved')
      end

      it 'rejects non-pending request' do
        deletion_request.update!(status: 'processing')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with action_type: reject' do
      it 'rejects deletion request with reason' do
        allow(NotificationService).to receive(:send_email).and_return(true)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                action_type: 'reject',
                reason: 'Request does not meet criteria',
                rejected_by_id: admin_user.id
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('rejected')
      end

      it 'requires rejection reason' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'reject' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with action_type: execute' do
      before do
        deletion_request.update!(
          status: 'approved',
          approved_at: Time.current,
          approved_by_id: admin_user.id
        )
      end

      it 'starts deletion execution' do
        allow(DataManagement::DeletionExecutionJob).to receive(:perform_later).and_return(true)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('processing')
      end

      it 'rejects non-approved request' do
        deletion_request.update!(status: 'pending')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with action_type: complete' do
      before do
        deletion_request.update!(
          status: 'processing',
          started_at: Time.current
        )
      end

      it 'completes deletion' do
        allow(NotificationService).to receive(:send_email).and_return(true)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                action_type: 'complete',
                deleted_records_count: 150,
                deletion_summary: { profile: 1, activities: 100, files: 49 }
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('completed')
        expect(deletion_request.deleted_records_count).to eq(150)
      end

      it 'rejects non-processing request' do
        deletion_request.update!(status: 'pending')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end

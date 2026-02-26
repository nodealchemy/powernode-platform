# frozen_string_literal: true

require 'rails_helper'

# Fix constant resolution: Api::V1::Internal::DataManagement module (from the namespaced
# controllers directory) shadows the top-level DataManagement module. Define the expected
# constants so the controller can resolve DataManagement::* correctly within its namespace.
unless defined?(Api::V1::Internal::DataManagement::DeletionRequest)
  Api::V1::Internal::DataManagement::DeletionRequest = ::DataManagement::DeletionRequest
end

RSpec.describe 'Api::V1::Internal::DataDeletionRequests', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  # Stub out side-effects globally
  before do
    allow(Audit::LogIntegrityService).to receive(:apply_integrity).and_return(true)
    allow(AuditLog).to receive(:log_compliance_event).and_return(true)
    allow(AuditLog).to receive(:log_action).and_return(true)
    allow(NotificationService).to receive(:send_email).and_return(true)
    allow(Notification).to receive(:create).and_return(Notification.new)

    # Stub job classes at both the top level and within the controller namespace
    # (the Api::V1::Internal::DataManagement module shadows top-level DataManagement)
    job_stub = Class.new { def self.perform_later(*); end }
    stub_const('DataManagement::DeletionProcessingJob', job_stub)
    stub_const('DataManagement::DeletionExecutionJob', job_stub)
    stub_const('Api::V1::Internal::DataManagement::DeletionProcessingJob', job_stub)
    stub_const('Api::V1::Internal::DataManagement::DeletionExecutionJob', job_stub)
  end

  # Helper to create deletion request
  let(:create_deletion_request) do
    ->(attrs = {}) {
      DataManagement::DeletionRequest.create!({
        account: account,
        user: user,
        deletion_type: 'full',
        reason: 'User requested account deletion',
        status: 'pending'
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call }

    context 'with internal authentication' do
      it 'returns deletion request details' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['data_deletion_request']).to include(
          'id' => deletion_request.id,
          'deletion_type' => 'full',
          'status' => 'pending'
        )
      end

      it 'includes detailed fields' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}", headers: internal_headers, as: :json

        data = json_response_data
        expect(data['data_deletion_request']).to have_key('data_types_to_delete')
        expect(data['data_deletion_request']).to have_key('reason')
      end
    end

    context 'when request does not exist' do
      it 'returns not found error' do
        get "/api/v1/internal/data_deletion_requests/#{SecureRandom.uuid}", headers: internal_headers, as: :json

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
          deletion_type: 'full',
          reason: 'GDPR deletion request',
          data_types_to_delete: [ 'profile', 'activity', 'audit_logs' ]
        }
      }
    end

    context 'with internal authentication' do
      it 'creates a new deletion request' do
        expect {
          post '/api/v1/internal/data_deletion_requests', params: valid_params, headers: internal_headers, as: :json
        }.to change(DataManagement::DeletionRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data

        expect(data['data_deletion_request']['status']).to eq('pending')
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_deletion_requests/:id' do
    let(:deletion_request) { create_deletion_request.call(status: 'pending') }

    context 'with action_type: approve' do
      it 'approves deletion request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve', processed_by_id: admin_user.id },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('approved')
      end

      it 'rejects non-pending request' do
        deletion_request.update!(status: 'processing', processing_started_at: Time.current)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: reject' do
      it 'rejects deletion request with reason' do
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

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: execute' do
      before do
        deletion_request.update!(
          status: 'approved',
          approved_at: Time.current,
          processed_by_id: admin_user.id
        )
      end

      it 'starts deletion execution' do
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

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with action_type: complete' do
      before do
        deletion_request.update!(
          status: 'processing',
          processing_started_at: Time.current
        )
      end

      it 'completes deletion' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                action_type: 'complete',
                deletion_log: [ { type: 'profile', count: 1 }, { type: 'activities', count: 100 }, { type: 'files', count: 49 } ]
              },
              headers: internal_headers,
              as: :json

        expect_success_response

        deletion_request.reload
        expect(deletion_request.status).to eq('completed')
      end

      it 'rejects non-processing request' do
        deletion_request.update!(status: 'pending')

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end

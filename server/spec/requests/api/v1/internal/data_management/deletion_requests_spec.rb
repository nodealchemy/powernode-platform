# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataDeletionRequests', type: :request do
  # Fix Ruby constant resolution: inside Api::V1::Internal, DataManagement::DeletionRequest
  # resolves to Api::V1::Internal::DataManagement::DeletionRequest (nonexistent) rather than
  # ::DataManagement::DeletionRequest. Define the alias so the controller can find it.
  before(:all) do
    unless Api::V1::Internal::DataManagement.const_defined?(:DeletionRequest, false)
      Api::V1::Internal::DataManagement.const_set(:DeletionRequest, ::DataManagement::DeletionRequest)
    end

    # Define stub job classes that the controller references but don't exist.
    # Must be defined both at top-level DataManagement:: and within
    # Api::V1::Internal::DataManagement:: since the controller's namespace resolution
    # will find the latter first.
    stub_job = Class.new(ApplicationJob) { def perform(*args); end }

    unless defined?(::DataManagement::DeletionProcessingJob)
      ::DataManagement.const_set(:DeletionProcessingJob, stub_job)
    end
    unless Api::V1::Internal::DataManagement.const_defined?(:DeletionProcessingJob, false)
      Api::V1::Internal::DataManagement.const_set(:DeletionProcessingJob, ::DataManagement::DeletionProcessingJob)
    end

    unless defined?(::DataManagement::DeletionExecutionJob)
      ::DataManagement.const_set(:DeletionExecutionJob, stub_job)
    end
    unless Api::V1::Internal::DataManagement.const_defined?(:DeletionExecutionJob, false)
      Api::V1::Internal::DataManagement.const_set(:DeletionExecutionJob, ::DataManagement::DeletionExecutionJob)
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
  let!(:deletion_request) do
    create(:data_management_deletion_request,
           user: user,
           account: account,
           status: 'pending')
  end

  before do
    # Stub NotificationService.send_email which the controller calls
    allow(NotificationService).to receive(:send_email).and_return(true)
  end

  describe 'GET /api/v1/internal/data_deletion_requests/:id' do
    context 'with valid service token' do
      it 'returns deletion request details' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']['data_deletion_request']

        expect(data['id']).to eq(deletion_request.id)
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
        expect(data['deletion_type']).to eq('full')
        # include_details: true adds these fields
        expect(data).to include(
          'completed_at',
          'error_message',
          'created_at'
        )
      end
    end

    context 'with non-existent deletion request' do
      it 'returns not found error' do
        get '/api/v1/internal/data_deletion_requests/non-existent-id',
            headers: internal_headers,
            as: :json

        expect_error_response('Data deletion request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'POST /api/v1/internal/data_deletion_requests' do
    context 'with valid service token' do
      let(:valid_params) do
        {
          data_deletion_request: {
            user_id: user.id,
            account_id: account.id,
            deletion_type: 'full',
            reason: 'User requested data deletion'
          }
        }
      end

      it 'creates a new deletion request' do
        expect do
          post '/api/v1/internal/data_deletion_requests',
               params: valid_params,
               headers: internal_headers,
               as: :json
        end.to change(DataManagement::DeletionRequest, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response

        data = json_response['data']['data_deletion_request']
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
      end

      it 'creates deletion request with metadata' do
        params = {
          data_deletion_request: {
            user_id: user.id,
            account_id: account.id,
            deletion_type: 'full',
            reason: 'GDPR request',
            metadata: { source: 'api' }
          }
        }

        post '/api/v1/internal/data_deletion_requests',
             params: params,
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        post '/api/v1/internal/data_deletion_requests',
             params: { data_deletion_request: { account_id: account.id } },
             headers: internal_headers,
             as: :json

        # Model validation fails (missing user, etc.) -> 422
        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/data_deletion_requests',
             params: { data_deletion_request: { user_id: user.id, account_id: account.id } },
             as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_deletion_requests/:id' do
    context 'approve action' do
      it 'approves a pending deletion request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve', processed_by_id: user.id },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']['data_deletion_request']
        expect(data['id']).to eq(deletion_request.id)
        expect(data['status']).to eq('approved')

        deletion_request.reload
        expect(deletion_request.status).to eq('approved')
        expect(deletion_request.approved_at).to be_present
      end

      it 'rejects approval of non-pending request' do
        deletion_request.update!(status: 'processing', processing_started_at: Time.current,
                                 approved_at: 1.day.ago, grace_period_ends_at: 1.hour.ago)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'reject action' do
      it 'rejects a pending deletion request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'reject', reason: 'Legal proceedings ongoing' },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.status).to eq('rejected')
        expect(deletion_request.rejection_reason).to eq('Legal proceedings ongoing')
      end

      it 'requires a rejection reason' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'reject' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'execute action' do
      before do
        deletion_request.update!(status: 'approved', approved_at: Time.current,
                                 grace_period_ends_at: 30.days.from_now)
      end

      it 'starts execution of an approved request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.status).to eq('processing')
        expect(deletion_request.processing_started_at).to be_present
      end

      it 'rejects execution of non-approved request' do
        deletion_request.update!(status: 'pending', approved_at: nil, grace_period_ends_at: nil)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'execute' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'complete action' do
      before do
        deletion_request.update!(status: 'processing', processing_started_at: Time.current,
                                 approved_at: 1.day.ago, grace_period_ends_at: 1.hour.ago)
      end

      it 'completes a processing request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'complete', deletion_log: [{ type: 'profile', deleted: true }] },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.status).to eq('completed')
        expect(deletion_request.completed_at).to be_present
      end

      it 'rejects completion of non-processing request' do
        deletion_request.update!(status: 'pending', processing_started_at: nil,
                                 approved_at: nil, grace_period_ends_at: nil)

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'complete' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'generic update (no action_type)' do
      it 'updates metadata on the request' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { data_deletion_request: { metadata: { note: 'updated' } } },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']['data_deletion_request']
        expect(data['id']).to eq(deletion_request.id)
      end
    end

    context 'with non-existent deletion request' do
      it 'returns not found error' do
        patch '/api/v1/internal/data_deletion_requests/non-existent-id',
              params: { action_type: 'approve' },
              headers: internal_headers,
              as: :json

        expect_error_response('Data deletion request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { action_type: 'approve' },
              as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'deletion request lifecycle' do
    it 'completes full lifecycle from pending to completed' do
      request = create(:data_management_deletion_request,
                       user: user,
                       account: account,
                       status: 'pending')

      # Step 1: Approve
      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: { action_type: 'approve', processed_by_id: user.id },
            headers: internal_headers,
            as: :json
      expect_success_response
      request.reload
      expect(request.status).to eq('approved')

      # Step 2: Execute
      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: { action_type: 'execute' },
            headers: internal_headers,
            as: :json
      expect_success_response
      request.reload
      expect(request.status).to eq('processing')

      # Step 3: Complete
      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: { action_type: 'complete' },
            headers: internal_headers,
            as: :json
      expect_success_response

      request.reload
      expect(request.status).to eq('completed')
      expect(request.completed_at).to be_present
    end

    it 'handles rejection during pending' do
      request = create(:data_management_deletion_request,
                       user: user,
                       account: account,
                       status: 'pending')

      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: {
              action_type: 'reject',
              reason: 'Request cannot be fulfilled'
            },
            headers: internal_headers,
            as: :json

      expect_success_response
      request.reload
      expect(request.status).to eq('rejected')
      expect(request.rejection_reason).to be_present
    end
  end
end

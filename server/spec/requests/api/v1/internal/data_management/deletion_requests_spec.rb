# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataManagement::DeletionRequests', type: :request do
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

  describe 'GET /api/v1/internal/data_deletion_requests/:id' do
    context 'with valid service token' do
      it 'returns deletion request details' do
        get "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(deletion_request.id)
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
        expect(data).to include(
          'scheduled_at',
          'completed_at',
          'error_message',
          'created_at',
          'updated_at'
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
          user_id: user.id,
          account_id: account.id,
          status: 'pending',
          scheduled_at: 30.days.from_now
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

        data = json_response['data']
        expect(data['user_id']).to eq(user.id)
        expect(data['account_id']).to eq(account.id)
        expect(data['status']).to eq('pending')
      end

      it 'creates deletion request with optional fields' do
        params = valid_params.merge(
          error_message: 'Test error',
          metadata: { source: 'api' }
        )

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
             params: { status: 'invalid' },
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/data_deletion_requests',
             params: { user_id: user.id, account_id: account.id },
             as: :json

        expect_error_response('Service token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/internal/data_deletion_requests/:id' do
    context 'with valid service token' do
      it 'updates deletion request status' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { status: 'processing' },
              headers: internal_headers,
              as: :json

        expect_success_response
        data = json_response['data']

        expect(data['id']).to eq(deletion_request.id)
        expect(data['status']).to eq('processing')

        deletion_request.reload
        expect(deletion_request.status).to eq('processing')
      end

      it 'updates deletion request to completed' do
        completed_at = Time.current

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { status: 'completed', completed_at: completed_at },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.status).to eq('completed')
        expect(deletion_request.completed_at).to be_present
      end

      it 'updates deletion request with error' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: {
                status: 'failed',
                error_message: 'Database connection failed'
              },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.status).to eq('failed')
        expect(deletion_request.error_message).to eq('Database connection failed')
      end

      it 'updates scheduled_at timestamp' do
        new_time = 60.days.from_now

        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { scheduled_at: new_time },
              headers: internal_headers,
              as: :json

        expect_success_response
        deletion_request.reload
        expect(deletion_request.scheduled_at).to be_within(1.second).of(new_time)
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { status: 'invalid_status' },
              headers: internal_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['success']).to be false
      end
    end

    context 'with non-existent deletion request' do
      it 'returns not found error' do
        patch '/api/v1/internal/data_deletion_requests/non-existent-id',
              params: { status: 'completed' },
              headers: internal_headers,
              as: :json

        expect_error_response('Data deletion request not found', 404)
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        patch "/api/v1/internal/data_deletion_requests/#{deletion_request.id}",
              params: { status: 'completed' },
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

      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: { status: 'processing' },
            headers: internal_headers,
            as: :json
      expect_success_response

      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: { status: 'completed', completed_at: Time.current },
            headers: internal_headers,
            as: :json
      expect_success_response

      request.reload
      expect(request.status).to eq('completed')
      expect(request.completed_at).to be_present
    end

    it 'handles failure during processing' do
      request = create(:data_management_deletion_request,
                       user: user,
                       account: account,
                       status: 'processing')

      patch "/api/v1/internal/data_deletion_requests/#{request.id}",
            params: {
              status: 'failed',
              error_message: 'User data could not be deleted'
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

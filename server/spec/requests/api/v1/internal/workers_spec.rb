# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Workers', type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }

  # Worker service authentication using config token
  let(:worker_service_headers) do
    worker_token = Rails.application.config.worker_token || 'test-worker-token'
    { 'Authorization' => "Bearer #{worker_token}" }
  end

  before do
    # Ensure worker token is configured
    allow(Rails.application.config).to receive(:worker_token).and_return('test-worker-token')
  end

  describe 'POST /api/v1/internal/workers/:id/test_results' do
    context 'with worker service authentication' do
      let(:test_results) do
        {
          test_type: 'connectivity',
          status: 'passed',
          duration_seconds: 1.5,
          redis_check: true,
          backend_check: true,
          timestamp: Time.current.iso8601
        }
      end

      it 'records test results' do
        allow_any_instance_of(Worker).to receive(:record_activity!).and_return(true)

        post "/api/v1/internal/workers/#{worker.id}/test_results",
             params: { test_results: test_results },
             headers: worker_service_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'worker_id' => worker.id,
          'test_status' => 'passed'
        )
      end

      it 'updates worker last_seen_at' do
        allow_any_instance_of(Worker).to receive(:record_activity!).and_return(true)

        expect_any_instance_of(Worker).to receive(:touch).with(:last_seen_at)

        post "/api/v1/internal/workers/#{worker.id}/test_results",
             params: { test_results: test_results },
             headers: worker_service_headers,
             as: :json

        expect_success_response
      end
    end

    context 'when worker does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/workers/nonexistent-id/test_results',
             params: { test_results: {} },
             headers: worker_service_headers,
             as: :json

        expect_error_response('Worker not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/workers/#{worker.id}/test_results",
             params: { test_results: {} },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid token' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/workers/#{worker.id}/test_results",
             params: { test_results: {} },
             headers: { 'Authorization' => 'Bearer invalid-token' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/workers/:id/ping' do
    context 'with worker service authentication' do
      it 'records ping' do
        allow_any_instance_of(Worker).to receive(:record_activity!).and_return(true)

        post "/api/v1/internal/workers/#{worker.id}/ping",
             headers: worker_service_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'worker_id' => worker.id,
          'worker_name' => worker.name
        )
      end

      it 'updates worker last_seen_at' do
        allow_any_instance_of(Worker).to receive(:record_activity!).and_return(true)

        expect_any_instance_of(Worker).to receive(:touch).with(:last_seen_at)

        post "/api/v1/internal/workers/#{worker.id}/ping",
             headers: worker_service_headers,
             as: :json

        expect_success_response
      end

      it 'includes timestamp in response' do
        allow_any_instance_of(Worker).to receive(:record_activity!).and_return(true)

        post "/api/v1/internal/workers/#{worker.id}/ping",
             headers: worker_service_headers,
             as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('timestamp')
      end
    end

    context 'when worker does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/workers/nonexistent-id/ping',
             headers: worker_service_headers,
             as: :json

        expect_error_response('Worker not found', 404)
      end
    end
  end
end

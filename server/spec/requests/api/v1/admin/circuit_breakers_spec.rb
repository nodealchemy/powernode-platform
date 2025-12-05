# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::CircuitBreakers', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :owner, account: account) }
  let(:regular_user) { create(:user, :member, account: account) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:regular_headers) { auth_headers_for(regular_user) }

  describe 'GET /api/v1/admin/circuit_breakers' do
    let!(:breaker1) { create(:circuit_breaker, :closed, service: 'ai_provider') }
    let!(:breaker2) { create(:circuit_breaker, :open, service: 'payment_gateway') }

    context 'with admin permissions' do
      it 'returns list of circuit breakers' do
        get '/api/v1/admin/circuit_breakers', headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breakers']).to be_an(Array)
        expect(data['circuit_breakers'].length).to eq(2)
        expect(data['meta']).to include('total', 'healthy_count', 'unhealthy_count')
      end

      it 'filters by service' do
        get '/api/v1/admin/circuit_breakers', params: { service: 'ai_provider' }, headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breakers'].length).to eq(1)
        expect(data['circuit_breakers'].first['service']).to eq('ai_provider')
      end

      it 'filters by state' do
        get '/api/v1/admin/circuit_breakers', params: { state: 'open' }, headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breakers'].length).to eq(1)
        expect(data['circuit_breakers'].first['state']).to eq('open')
      end

      it 'filters by health status' do
        get '/api/v1/admin/circuit_breakers', params: { health_status: 'healthy' }, headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breakers'].all? { |cb| cb['state'] == 'closed' }).to be true
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get '/api/v1/admin/circuit_breakers', headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view circuit breakers', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/circuit_breakers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/admin/circuit_breakers/:id' do
    let(:breaker) { create(:circuit_breaker, :closed) }

    context 'with admin permissions' do
      it 'returns circuit breaker details' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}", headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breaker']).to include(
          'id' => breaker.id,
          'name' => breaker.name,
          'service' => breaker.service,
          'state' => 'closed'
        )
        expect(data['circuit_breaker']).to have_key('recent_events')
      end

      it 'returns not found for non-existent breaker' do
        get "/api/v1/admin/circuit_breakers/#{SecureRandom.uuid}", headers: admin_headers, as: :json

        expect_error_response('Circuit breaker not found', 404)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view circuit breakers', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/circuit_breakers' do
    let(:valid_params) do
      {
        circuit_breaker: {
          name: 'test_breaker',
          service: 'ai_provider',
          failure_threshold: 5,
          success_threshold: 2,
          timeout_seconds: 30,
          reset_timeout_seconds: 60,
          configuration: { auto_reset: true }
        }
      }
    end

    context 'with admin permissions' do
      it 'creates a new circuit breaker' do
        expect {
          post '/api/v1/admin/circuit_breakers', params: valid_params, headers: admin_headers, as: :json
        }.to change(CircuitBreaker, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response
        expect(data['circuit_breaker']).to include(
          'name' => 'test_breaker',
          'service' => 'ai_provider',
          'state' => 'closed'
        )
        expect(data['message']).to eq('Circuit breaker created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(circuit_breaker: { name: nil })

        post '/api/v1/admin/circuit_breakers', params: invalid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        post '/api/v1/admin/circuit_breakers', params: valid_params, headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage circuit breakers', 403)
      end
    end
  end

  describe 'PATCH /api/v1/admin/circuit_breakers/:id' do
    let(:breaker) { create(:circuit_breaker, :closed) }
    let(:update_params) do
      {
        circuit_breaker: {
          failure_threshold: 10,
          success_threshold: 3
        }
      }
    end

    context 'with admin permissions' do
      it 'updates the circuit breaker' do
        patch "/api/v1/admin/circuit_breakers/#{breaker.id}",
              params: update_params,
              headers: admin_headers,
              as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breaker']['failure_threshold']).to eq(10)
        expect(data['circuit_breaker']['success_threshold']).to eq(3)
        expect(data['message']).to eq('Circuit breaker updated successfully')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { circuit_breaker: { failure_threshold: -1 } }

        patch "/api/v1/admin/circuit_breakers/#{breaker.id}",
              params: invalid_params,
              headers: admin_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/admin/circuit_breakers/#{breaker.id}",
              params: update_params,
              headers: regular_headers,
              as: :json

        expect_error_response('Insufficient permissions to manage circuit breakers', 403)
      end
    end
  end

  describe 'DELETE /api/v1/admin/circuit_breakers/:id' do
    let!(:breaker) { create(:circuit_breaker, :closed) }

    context 'with admin permissions' do
      it 'deletes the circuit breaker' do
        expect {
          delete "/api/v1/admin/circuit_breakers/#{breaker.id}", headers: admin_headers, as: :json
        }.to change(CircuitBreaker, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('Circuit breaker deleted successfully')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        delete "/api/v1/admin/circuit_breakers/#{breaker.id}", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage circuit breakers', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/circuit_breakers/:id/reset' do
    let(:breaker) { create(:circuit_breaker, :open, failure_count: 5) }

    context 'with admin permissions' do
      it 'resets the circuit breaker' do
        post "/api/v1/admin/circuit_breakers/#{breaker.id}/reset", headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breaker']['state']).to eq('closed')
        expect(data['circuit_breaker']['failure_count']).to eq(0)
        expect(data['message']).to eq('Circuit breaker reset successfully')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        post "/api/v1/admin/circuit_breakers/#{breaker.id}/reset", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage circuit breakers', 403)
      end
    end
  end

  describe 'GET /api/v1/admin/circuit_breakers/:id/health' do
    let(:breaker) { create(:circuit_breaker, :closed) }

    before do
      create_list(:circuit_breaker_event, 5, :success, circuit_breaker: breaker)
      create_list(:circuit_breaker_event, 2, :failure, circuit_breaker: breaker)
    end

    context 'with admin permissions' do
      it 'returns health metrics' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}/health", headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breaker_id']).to eq(breaker.id)
        expect(data['health_metrics']).to include(
          'state' => 'closed',
          'total_requests' => 7
        )
        expect(data['health_metrics']).to have_key('success_rate')
        expect(data['health_metrics']).to have_key('failure_rate')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}/health", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view circuit breakers', 403)
      end
    end
  end

  describe 'GET /api/v1/admin/circuit_breakers/:id/events' do
    let(:breaker) { create(:circuit_breaker, :closed) }

    before do
      create_list(:circuit_breaker_event, 15, circuit_breaker: breaker)
    end

    context 'with admin permissions' do
      it 'returns recent events' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}/events", headers: admin_headers, as: :json

        expect_success_response
        data = json_response
        expect(data['circuit_breaker_id']).to eq(breaker.id)
        expect(data['events']).to be_an(Array)
        expect(data['events'].length).to be <= 50
        expect(data['meta']).to include('count', 'limit')
      end

      it 'respects limit parameter' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}/events",
            params: { limit: 5 },
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response
        expect(data['events'].length).to eq(5)
        expect(data['meta']['limit']).to eq(5)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get "/api/v1/admin/circuit_breakers/#{breaker.id}/events", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view circuit breakers', 403)
      end
    end
  end
end

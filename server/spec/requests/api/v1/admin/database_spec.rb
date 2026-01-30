# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Database', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: ['system.admin']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin/database/pool_stats' do
    context 'with admin access' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns database pool statistics' do
        get '/api/v1/admin/database/pool_stats', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include('size', 'checked_out', 'checked_in')
      end

      it 'includes dead connection count' do
        get '/api/v1/admin/database/pool_stats', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('dead')
      end

      it 'includes waiting count' do
        get '/api/v1/admin/database/pool_stats', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('waiting')
      end
    end

    context 'with worker token' do
      let(:worker_token) { 'test-worker-token' }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('WORKER_TOKEN').and_return(worker_token)
      end

      it 'allows access with valid worker token' do
        get '/api/v1/admin/database/pool_stats',
            headers: { 'Authorization' => "Bearer #{worker_token}" },
            as: :json

        expect_success_response
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/database/pool_stats', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/admin/database/ping' do
    context 'with admin access' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns database ping status' do
        get '/api/v1/admin/database/ping', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'status' => 'ok'
        )
      end

      it 'includes response time' do
        get '/api/v1/admin/database/ping', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('response_time_ms')
      end

      it 'includes timestamp' do
        get '/api/v1/admin/database/ping', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('timestamp')
      end
    end
  end

  describe 'GET /api/v1/admin/database/health' do
    context 'with admin access' do
      let(:headers) { auth_headers_for(admin_user) }

      it 'returns comprehensive health check' do
        get '/api/v1/admin/database/health', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('status')
        expect(response_data['data']).to have_key('checks')
      end

      it 'includes connection check' do
        get '/api/v1/admin/database/health', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['checks']).to have_key('connection')
      end

      it 'includes pool utilization check' do
        get '/api/v1/admin/database/health', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['checks']).to have_key('pool_utilization')
      end

      it 'includes response time check' do
        get '/api/v1/admin/database/health', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['checks']).to have_key('response_time')
      end

      it 'includes timestamp' do
        get '/api/v1/admin/database/health', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('timestamp')
      end
    end
  end
end

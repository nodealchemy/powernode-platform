# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Health', type: :request do
  describe 'GET /health' do
    it 'returns healthy status' do
      get '/health', as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['status']).to eq('healthy')
      expect(response_data['data']).to have_key('timestamp')
      expect(response_data['data']).to have_key('uptime_seconds')
      expect(response_data['data']).to have_key('version')
    end

    it 'does not require authentication' do
      get '/health', as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /health/detailed' do
    before do
      # Mock database check
      allow(ActiveRecord::Base.connection).to receive(:execute).and_return(true)
      allow(ActiveRecord::Base.connection_pool).to receive(:size).and_return(5)
      allow(ActiveRecord::Base.connection_pool).to receive(:connections).and_return([])
    end

    it 'returns detailed health information' do
      get '/health/detailed', as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']).to have_key('status')
      expect(response_data['data']).to have_key('checks')
    end

    it 'includes database check' do
      get '/health/detailed', as: :json

      response_data = json_response

      expect(response_data['data']['checks']).to have_key('database')
      expect(response_data['data']['checks']['database']).to have_key('status')
    end

    it 'includes redis check' do
      get '/health/detailed', as: :json

      response_data = json_response

      expect(response_data['data']['checks']).to have_key('redis')
    end

    it 'includes memory check' do
      get '/health/detailed', as: :json

      response_data = json_response

      expect(response_data['data']['checks']).to have_key('memory')
    end

    it 'includes disk check' do
      get '/health/detailed', as: :json

      response_data = json_response

      expect(response_data['data']['checks']).to have_key('disk')
    end

    it 'reports overall status based on component health' do
      get '/health/detailed', as: :json

      response_data = json_response

      expect([ 'healthy', 'degraded' ]).to include(response_data['data']['status'])
    end
  end

  describe 'GET /health/ready' do
    context 'when all services are healthy' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_return(true)
        allow(Redis).to receive(:new).and_return(double(ping: 'PONG'))
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('REDIS_URL').and_return('redis://localhost:6379')
      end

      it 'returns ready status' do
        get '/health/ready', as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['ready']).to be true
      end
    end

    context 'when database is unhealthy' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns service unavailable' do
        get '/health/ready', as: :json

        expect(response).to have_http_status(:service_unavailable)
      end
    end
  end

  describe 'GET /health/live' do
    it 'returns live status' do
      get '/health/live', as: :json

      expect_success_response
      response_data = json_response

      expect(response_data['data']['live']).to be true
    end

    it 'does not require authentication' do
      get '/health/live', as: :json

      expect(response).to have_http_status(:ok)
    end

    it 'always returns live (simple liveness check)' do
      # Liveness check should always succeed if the app is running
      get '/health/live', as: :json

      expect(response).to have_http_status(:ok)
    end
  end
end

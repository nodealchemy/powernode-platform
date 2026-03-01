# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Services', type: :request do
  # Worker JWT authentication via InternalBaseController
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/services/health_check' do
    context 'with internal authentication' do
      it 'returns health status for all services' do
        post '/api/v1/internal/services/health_check', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('database')
        expect(data).to have_key('redis')
        expect(data).to have_key('timestamp')
      end

      it 'includes database health status' do
        post '/api/v1/internal/services/health_check', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['database']).to be_in([ 'healthy', 'unhealthy' ])
      end

      it 'includes redis health status' do
        post '/api/v1/internal/services/health_check', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['redis']).to be_in([ 'healthy', 'unhealthy' ])
      end

      it 'includes timestamp of health check' do
        freeze_time do
          post '/api/v1/internal/services/health_check', headers: internal_headers, as: :json

          expect_success_response
          data = json_response_data

          expect(Time.parse(data['timestamp'])).to be_within(1.second).of(Time.current)
        end
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/services/health_check', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/services/generate_config' do
    context 'with internal authentication' do
      it 'generates service configuration' do
        post '/api/v1/internal/services/generate_config', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('api_version')
        expect(data).to have_key('environment')
        expect(data).to have_key('services')
        expect(data).to have_key('timestamp')
      end

      it 'includes API version' do
        post '/api/v1/internal/services/generate_config', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['api_version']).to eq('v1')
      end

      it 'includes current environment' do
        post '/api/v1/internal/services/generate_config', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['environment']).to eq(Rails.env)
      end

      it 'includes available services' do
        post '/api/v1/internal/services/generate_config', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['services']).to be_an(Array)
        expect(data['services'].length).to be > 0
      end
    end
  end

  describe 'POST /api/v1/internal/services/service_discovery' do
    context 'with internal authentication' do
      it 'returns discovered services' do
        post '/api/v1/internal/services/service_discovery', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('services')
        expect(data['services']).to be_an(Array)
      end

      it 'includes service details' do
        post '/api/v1/internal/services/service_discovery', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        services = data['services']
        first_service = services.first

        expect(first_service).to have_key('name')
        expect(first_service).to have_key('url')
        expect(first_service).to have_key('status')
      end
    end
  end

  describe 'POST /api/v1/internal/services/validate' do
    context 'with internal authentication' do
      it 'validates service configuration' do
        post '/api/v1/internal/services/validate', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('valid')
        expect(data).to have_key('errors')
      end

      it 'returns valid status' do
        post '/api/v1/internal/services/validate', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['valid']).to be true
        expect(data['errors']).to be_empty
      end
    end
  end

  describe 'POST /api/v1/internal/services/test_connectivity' do
    context 'with internal authentication' do
      it 'tests connectivity to external services' do
        post '/api/v1/internal/services/test_connectivity', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('database')
        expect(data).to have_key('redis')
      end

      it 'includes database connectivity test result' do
        post '/api/v1/internal/services/test_connectivity', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['database']).to have_key('connected')
      end

      it 'includes redis connectivity test result' do
        post '/api/v1/internal/services/test_connectivity', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data['redis']).to have_key('connected')
      end

      it 'includes latency metrics for successful connections' do
        post '/api/v1/internal/services/test_connectivity', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        redis_result = data['redis']
        if redis_result['connected']
          expect(redis_result).to have_key('latency_ms')
          expect(redis_result['latency_ms']).to be_a(Numeric)
        end
      end
    end
  end

  describe 'POST /api/v1/internal/services/validate_services' do
    context 'with internal authentication' do
      it 'validates all registered services' do
        post '/api/v1/internal/services/validate_services', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to have_key('validations')
        expect(data['validations']).to be_an(Array)
      end

      it 'includes validation status for each service' do
        post '/api/v1/internal/services/validate_services', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        validations = data['validations']
        first_validation = validations.first

        expect(first_validation).to have_key('name')
        expect(first_validation).to have_key('valid')
      end

      it 'marks all services as valid' do
        post '/api/v1/internal/services/validate_services', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        validations = data['validations']
        expect(validations.all? { |v| v['valid'] }).to be true
      end
    end
  end
end

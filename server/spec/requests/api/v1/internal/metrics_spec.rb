# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Metrics', type: :request do
  # Internal service authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/metrics/jobs' do
    context 'with internal authentication' do
      it 'returns job metrics' do
        get '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        job_metrics = response_data['data']['data']['job_metrics']
        expect(job_metrics).to have_key('queues')
        expect(job_metrics).to have_key('processed')
        expect(job_metrics).to have_key('failed')
        expect(job_metrics).to have_key('scheduled')
        expect(job_metrics).to have_key('workers')
      end

      it 'includes queue statistics' do
        get '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        job_metrics = response_data['data']['data']['job_metrics']
        expect(job_metrics['queues']).to be_a(Hash)
      end

      it 'includes processed job statistics' do
        get '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        processed = response_data['data']['data']['job_metrics']['processed']
        expect(processed).to have_key('total')
        expect(processed).to have_key('today')
        expect(processed).to have_key('success_rate')
      end

      it 'includes failed job statistics' do
        get '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        failed = response_data['data']['data']['job_metrics']['failed']
        expect(failed).to have_key('total')
        expect(failed).to have_key('today')
        expect(failed).to have_key('retry_queue')
        expect(failed).to have_key('dead_queue')
      end

      it 'includes worker statistics' do
        get '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        workers = response_data['data']['data']['job_metrics']['workers']
        expect(workers).to have_key('active')
        expect(workers).to have_key('processes')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/metrics/jobs', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/metrics/errors' do
    context 'with internal authentication' do
      before do
        create(:system_error, error_class: 'RuntimeError', message: 'Test error 1', severity: 'high')
        create(:system_error, error_class: 'StandardError', message: 'Test error 2', severity: 'medium')
        create(:system_error, error_class: 'RuntimeError', message: 'Test error 3', severity: 'low')
      end

      it 'returns error metrics' do
        get '/api/v1/internal/metrics/errors', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        error_metrics = response_data['data']['data']['error_metrics']
        expect(error_metrics).to have_key('total_count')
        expect(error_metrics).to have_key('by_class')
        expect(error_metrics).to have_key('time_range')
        expect(error_metrics).to have_key('recent_errors')
      end

      it 'groups errors by class' do
        get '/api/v1/internal/metrics/errors', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        by_class = response_data['data']['data']['error_metrics']['by_class']
        expect(by_class['RuntimeError']).to eq(2)
        expect(by_class['StandardError']).to eq(1)
      end

      it 'accepts time range parameter' do
        get '/api/v1/internal/metrics/errors',
            headers: internal_headers,
            params: { range: '1h' },
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['error_metrics']['time_range']).to eq('1h')
      end

      it 'includes recent error details' do
        get '/api/v1/internal/metrics/errors', headers: internal_headers, as: :json

        expect_success_response
        response_data = json_response

        recent_errors = response_data['data']['data']['error_metrics']['recent_errors']
        expect(recent_errors).to be_an(Array)
        expect(recent_errors.length).to be <= 100

        first_error = recent_errors.first
        expect(first_error).to include('id', 'error_class', 'message', 'severity', 'occurred_at')
      end
    end
  end

  describe 'GET /api/v1/internal/metrics/custom' do
    context 'with internal authentication' do
      it 'requires metrics parameter' do
        get '/api/v1/internal/metrics/custom', headers: internal_headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns custom metrics when requested' do
        get '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'memory_usage,cpu_usage' },
            as: :json

        expect_success_response
        response_data = json_response

        custom_metrics = response_data['data']['data']['custom_metrics']
        expect(custom_metrics).to have_key('memory_usage')
        expect(custom_metrics).to have_key('cpu_usage')
      end

      it 'accepts time range and interval parameters' do
        get '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'cpu_usage', range: '6h', interval: '10m' },
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['data']['time_range']).to eq('6h')
        expect(response_data['data']['data']['interval']).to eq('10m')
      end

      it 'returns memory usage metrics' do
        get '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'memory_usage' },
            as: :json

        expect_success_response
        response_data = json_response

        memory = response_data['data']['data']['custom_metrics']['memory_usage']
        expect(memory).to have_key('total_kb')
        expect(memory).to have_key('used_kb')
        expect(memory).to have_key('available_kb')
        expect(memory).to have_key('usage_percent')
      end

      it 'returns cpu usage metrics' do
        get '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'cpu_usage' },
            as: :json

        expect_success_response
        response_data = json_response

        cpu = response_data['data']['data']['custom_metrics']['cpu_usage']
        expect(cpu).to have_key('load_1m')
        expect(cpu).to have_key('load_5m')
        expect(cpu).to have_key('load_15m')
        expect(cpu).to have_key('cpu_count')
        expect(cpu).to have_key('normalized_load')
      end
    end
  end
end

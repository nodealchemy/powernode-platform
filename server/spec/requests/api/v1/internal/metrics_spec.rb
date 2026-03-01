# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Metrics', type: :request do
  # Worker JWT authentication via InternalBaseController
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/metrics/jobs' do
    context 'with internal authentication' do
      it 'returns job metrics' do
        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        job_metrics = data['job_metrics']
        expect(job_metrics).to have_key('queues')
        expect(job_metrics).to have_key('processed')
        expect(job_metrics).to have_key('failed')
        expect(job_metrics).to have_key('scheduled')
        expect(job_metrics).to have_key('workers')
      end

      it 'includes queue statistics' do
        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        job_metrics = data['job_metrics']
        expect(job_metrics['queues']).to be_a(Hash)
      end

      it 'includes processed job statistics' do
        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        processed = data['job_metrics']['processed']
        expect(processed).to have_key('total')
        expect(processed).to have_key('today')
        expect(processed).to have_key('success_rate')
      end

      it 'includes failed job statistics' do
        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        failed = data['job_metrics']['failed']
        expect(failed).to have_key('total')
        expect(failed).to have_key('today')
        expect(failed).to have_key('retry_queue')
        expect(failed).to have_key('dead_queue')
      end

      it 'includes worker statistics' do
        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        data = json_response_data

        workers = data['job_metrics']['workers']
        expect(workers).to have_key('active')
        expect(workers).to have_key('processes')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/metrics/jobs', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/metrics/custom' do
    context 'with internal authentication' do
      it 'requires metrics parameter' do
        post '/api/v1/internal/metrics/custom', headers: internal_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns custom metrics when requested' do
        post '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'memory_usage,cpu_usage' },
            as: :json

        expect_success_response
        data = json_response_data

        custom_metrics = data['custom_metrics']
        expect(custom_metrics).to have_key('memory_usage')
        expect(custom_metrics).to have_key('cpu_usage')
      end

      it 'accepts time range and interval parameters' do
        post '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'cpu_usage', range: '6h', interval: '10m' },
            as: :json

        expect_success_response
        data = json_response_data

        expect(data['time_range']).to eq('6h')
        expect(data['interval']).to eq('10m')
      end

      it 'returns memory usage metrics' do
        post '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'memory_usage' },
            as: :json

        expect_success_response
        data = json_response_data

        memory = data['custom_metrics']['memory_usage']
        expect(memory).to have_key('total_kb')
        expect(memory).to have_key('used_kb')
        expect(memory).to have_key('available_kb')
        expect(memory).to have_key('usage_percent')
      end

      it 'returns cpu usage metrics' do
        post '/api/v1/internal/metrics/custom',
            headers: internal_headers,
            params: { metrics: 'cpu_usage' },
            as: :json

        expect_success_response
        data = json_response_data

        cpu = data['custom_metrics']['cpu_usage']
        expect(cpu).to have_key('load_1m')
        expect(cpu).to have_key('load_5m')
        expect(cpu).to have_key('load_15m')
        expect(cpu).to have_key('cpu_count')
        expect(cpu).to have_key('normalized_load')
      end
    end
  end
end

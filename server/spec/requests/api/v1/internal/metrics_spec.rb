# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Metrics', type: :request do
  # Worker JWT authentication via InternalBaseController
  let(:internal_account) { create(:account) }
  let(:internal_worker) { create(:worker, account: internal_account) }
  let(:internal_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
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

      # `processed`, `failed` and `workers` are SCALAR counters, not nested
      # hashes. Three examples here previously drilled into them for sub-keys
      # ('total'/'today', 'retry_queue', 'active'/'processes'), a shape neither
      # branch of the controller has ever produced — so they failed on
      # `nil.has_key?` rather than on anything the endpoint got wrong.
      it 'reports available=false with null counters when the worker is unreachable' do
        # Stubbed rather than assumed: a developer box often HAS a worker
        # listening on :4567, so leaving this to the environment makes the
        # example pass on one machine and fail on another.
        allow(WorkerJobService).to receive(:fetch_sidekiq_stats).and_return(nil)

        post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

        expect_success_response
        job_metrics = json_response_data['job_metrics']

        # The deliberate honest-fallback branch: this Rails API runs no Sidekiq,
        # so with the worker down there is nothing to report. Reporting zeros
        # here would read as "healthy, nothing failed" — the nils are the point.
        expect(job_metrics['available']).to be(false)
        expect(job_metrics['source']).to eq('worker_unreachable')
        expect(job_metrics.values_at('processed', 'failed', 'workers', 'success_rate')).to all(be_nil)
        expect(job_metrics['queues']).to eq({})
      end

      context 'when the worker reports Sidekiq stats' do
        # Otherwise unexercised: the counters only ever arrive over the worker's
        # HTTP API, and the worker is unreachable in test.
        before do
          allow(WorkerJobService).to receive(:fetch_sidekiq_stats).and_return(
            'data' => {
              'processed' => 990, 'failed' => 10, 'enqueued' => 3,
              'scheduled_size' => 4, 'retry_size' => 5, 'dead_size' => 6,
              'workers_size' => 2, 'default_queue_latency' => 0.25,
              'queues' => { 'default' => 3 }, 'timestamp' => '2026-07-30T00:00:00Z'
            }
          )
        end

        it 'maps the worker counters onto the response' do
          post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

          expect_success_response
          job_metrics = json_response_data['job_metrics']

          expect(job_metrics['available']).to be(true)
          expect(job_metrics['source']).to eq('worker_sidekiq')
          expect(job_metrics['processed']).to eq(990)
          expect(job_metrics['failed']).to eq(10)
          expect(job_metrics['scheduled']).to eq(4)
          expect(job_metrics['retries']).to eq(5)
          expect(job_metrics['dead']).to eq(6)
          expect(job_metrics['workers']).to eq(2)
          expect(job_metrics['queues']).to eq('default' => 3)
        end

        it 'computes the lifetime success rate from the cumulative counters' do
          post '/api/v1/internal/metrics/jobs', headers: internal_headers, as: :json

          expect(json_response_data['job_metrics']['success_rate']).to eq(99.0)
        end
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

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe TestWorkerJob, type: :job do
  subject { described_class }

  let(:worker_id) { 'wrk_123' }
  let(:worker_name) { 'primary-worker' }
  let(:options) do
    {
      'test_type' => 'worker_connectivity_test',
      'worker_id' => worker_id,
      'timestamp' => Time.current.to_i
    }
  end
  let(:api_client_double) { double('BackendApiClient') }
  let(:job_instance) { subject.new }

  before do
    mock_powernode_worker_config
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow(Sidekiq).to receive(:redis).and_yield(instance_double('Redis', ping: 'PONG'))
  end

  it_behaves_like 'a base job', described_class

  describe 'job configuration' do
    it 'uses the services queue' do
      expect(subject.sidekiq_options['queue'].to_s).to eq('services')
    end

    it 'has retry count of 1' do
      expect(subject.sidekiq_options['retry']).to eq(1)
    end
  end

  describe '#execute' do
    context 'when the worker is healthy' do
      before do
        allow(api_client_double).to receive(:post).and_return({ 'success' => true })
      end

      it 'matches the producer signature exactly: [worker_id, worker_name, options_hash]' do
        # WorkerJobService#enqueue_test_worker_job enqueues exactly these 3
        # positional args — a signature mismatch here would raise ArgumentError
        # on every real invocation.
        expect { job_instance.execute(worker_id, worker_name, options) }.not_to raise_error
      end

      it 'reports a completion signal back to the server (the observable result)' do
        job_instance.execute(worker_id, worker_name, options)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/workers/#{worker_id}/test_results",
          hash_including(
            test_results: hash_including(
              status: 'passed',
              redis_check: true,
              backend_check: true
            )
          )
        )
      end

      it 'returns a passed status when the redis check succeeds' do
        result = job_instance.execute(worker_id, worker_name, options)

        expect(result[:status]).to eq('passed')
        expect(result[:redis_check]).to eq(true)
      end
    end

    context 'when the redis check fails but the backend is reachable' do
      before do
        allow(Sidekiq).to receive(:redis).and_raise(StandardError, 'connection refused')
        allow(api_client_double).to receive(:post).and_return({ 'success' => true })
      end

      it 'reports a failed status rather than silently swallowing the problem' do
        result = job_instance.execute(worker_id, worker_name, options)

        expect(result[:status]).to eq('failed')
        expect(result[:redis_check]).to eq(false)
        expect(api_client_double).to have_received(:post).with(
          "/api/v1/workers/#{worker_id}/test_results",
          hash_including(test_results: hash_including(status: 'failed', redis_check: false))
        )
      end
    end

    # The negative case for the finding: a genuinely unreachable backend must
    # NOT be reported as a completed/healthy test. Nothing in this job
    # rescues the report_test_results POST, so a real connectivity failure
    # propagates as a job failure instead of being swallowed into a fake
    # success — the server never gets a "test_completed" activity, so a
    # human reading Worker#worker_activities correctly sees no completion
    # rather than a fabricated healthy one.
    context 'when the backend is unreachable' do
      before do
        allow(api_client_double).to receive(:post)
          .and_raise(BackendApiClient::ApiError.new('Connection failed', 503))
      end

      it 'propagates the error instead of reporting a fake completion' do
        expect { job_instance.execute(worker_id, worker_name, options) }
          .to raise_error(BackendApiClient::ApiError)
      end
    end
  end
end

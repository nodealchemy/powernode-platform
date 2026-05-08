# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillingProvisioningMeterJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with retry logic'

  before do
    mock_powernode_worker_config
    # WorkerJwt.token reads worker_id and jwt_secret_key from config; stub the
    # token directly so we don't need to expand the worker config double.
    allow(WorkerJwt).to receive(:token).and_return('test-worker-token-123')
    stub_backend_api_success(:post, '/api/v1/internal/billing/provisioning/meter/rollup',
                             { 'success' => true, 'data' => { 'metered_count' => 4, 'invoiced_count' => 1 } })
  end

  describe '#execute' do
    it 'posts to the billing provisioning meter rollup endpoint' do
      described_class.new.execute
      expect(WebMock).to have_requested(:post, %r{/api/v1/internal/billing/provisioning/meter/rollup}).at_least_once
    end

    it 'returns the rollup result payload' do
      result = described_class.new.execute
      expect(result).to be_a(Hash)
      expect(result['success']).to eq(true)
      expect(result.dig('data', 'metered_count')).to eq(4)
    end

    it 'logs the metered/invoiced counts' do
      logs = []
      job  = described_class.new
      allow(job).to receive(:log_info) { |msg, **_opts| logs << msg }
      allow(job).to receive(:log_warn)
      allow(job).to receive(:log_error)
      job.execute
      expect(logs).to include(match(/Billing provisioning meter rollup completed/))
    end

    it 'sends the supplied timestamp through to the rollup endpoint' do
      now = Time.utc(2026, 5, 8, 12, 0, 0).iso8601
      described_class.new.execute(now)
      expect(WebMock).to have_requested(:post, %r{/api/v1/internal/billing/provisioning/meter/rollup})
                          .with(body: hash_including('now' => now))
    end
  end

  context 'when the rollup endpoint reports a failure' do
    before do
      WebMock.reset!
      allow(WorkerJwt).to receive(:token).and_return('test-worker-token-123')
      stub_backend_api_success(:post, '/api/v1/internal/billing/provisioning/meter/rollup',
                               { 'success' => false, 'error' => 'transient db error' })
    end

    it 'returns the failure payload without raising' do
      expect { described_class.new.execute }.not_to raise_error
    end
  end

  context 'when the API client raises a non-retryable error' do
    before do
      WebMock.reset!
      allow(WorkerJwt).to receive(:token).and_return('test-worker-token-123')
      stub_backend_api_error(:post, '/api/v1/internal/billing/provisioning/meter/rollup',
                             status: 404, error_message: 'rollup endpoint missing')
    end

    it 're-raises so Sidekiq retries the job' do
      expect { described_class.new.execute }.to raise_error(BackendApiClient::ApiError)
    end
  end
end

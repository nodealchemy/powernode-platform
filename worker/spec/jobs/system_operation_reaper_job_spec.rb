# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SystemOperationReaperJob, type: :job do
  subject { described_class } # required by 'a job with API communication' / 'a job with logging' shared examples

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with logging'

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(SystemExecuteOperationJob).to receive(:perform_async)
  end

  describe '#execute' do
    context 'when there is no stuck work' do
      before do
        allow(api_client).to receive(:get).and_return('data' => { 'operations' => [] })
      end

      it 'reports zero counts' do
        result = job.execute
        expect(result).to eq(reaped_pending: 0, reaped_running: 0)
      end
    end

    context 'when there are stuck pending operations beyond threshold' do
      let(:stuck_op) do
        {
          'id' => 'op-stuck-1',
          'created_at' => (Time.current - 10.minutes).iso8601
        }
      end
      let(:fresh_op) do
        {
          'id' => 'op-fresh-1',
          'created_at' => (Time.current - 1.minute).iso8601
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'pending'))
          .and_return('data' => { 'operations' => [stuck_op, fresh_op] })
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'running'))
          .and_return('data' => { 'operations' => [] })
      end

      it 're-enqueues only the stuck pending op' do
        result = job.execute

        expect(SystemExecuteOperationJob).to have_received(:perform_async).with('op-stuck-1').once
        expect(SystemExecuteOperationJob).not_to have_received(:perform_async).with('op-fresh-1')
        expect(result[:reaped_pending]).to eq(1)
      end
    end

    context 'when there are stuck running operations beyond threshold' do
      let(:stuck_op) do
        {
          'id' => 'op-stuck-run',
          'started_at' => (Time.current - 90.minutes).iso8601
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'pending'))
          .and_return('data' => { 'operations' => [] })
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'running'))
          .and_return('data' => { 'operations' => [stuck_op] })
        allow(api_client).to receive(:post).and_return({})
      end

      it 'POSTs /fail with an execution_lost message' do
        result = job.execute

        expect(api_client).to have_received(:post).with(
          '/api/v1/system/worker_api/operations/op-stuck-run/fail',
          hash_including(:error_message)
        )
        expect(result[:reaped_running]).to eq(1)
      end
    end

    context 'when the API call fails for the pending sweep' do
      let(:api_error) { BackendApiClient::ApiError.new('boom') }

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'pending'))
          .and_raise(api_error)
        allow(api_client).to receive(:get)
          .with('/api/v1/system/worker_api/operations', hash_including(status: 'running'))
          .and_return('data' => { 'operations' => [] })
      end

      it 'returns zero for that sweep without raising — running sweep still runs' do
        result = job.execute
        expect(result[:reaped_pending]).to eq(0)
        expect(result[:reaped_running]).to eq(0)
      end
    end
  end

  describe '#stuck?' do
    it 'returns false for blank timestamp' do
      expect(job.send(:stuck?, '', 60)).to be false
      expect(job.send(:stuck?, nil, 60)).to be false
    end

    it 'returns false for unparseable strings' do
      expect(job.send(:stuck?, 'not-a-date', 60)).to be false
    end

    it 'returns true when timestamp is older than threshold' do
      expect(job.send(:stuck?, (Time.current - 10.minutes).iso8601, 300)).to be true
    end

    it 'returns false when timestamp is newer than threshold' do
      expect(job.send(:stuck?, (Time.current - 1.minute).iso8601, 300)).to be false
    end
  end

  describe 'sidekiq_options' do
    it 'declares retry: 0 (failures handled on next hourly cycle)' do
      expect(described_class.get_sidekiq_options['retry']).to eq(0)
    end
  end
end

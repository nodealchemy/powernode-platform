# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SystemExecuteOperationJob, type: :job do
  subject { described_class } # required by 'a job with API communication' / 'a job with logging' shared examples

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with logging'

  let(:job) { described_class.new }
  let(:operation_id) { 'op-12345' }
  let(:job_args) { operation_id } # consumed by 'a job with logging' shared example to call .perform(operation_id)
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
  end

  describe '#execute' do
    context 'when the server returns 200' do
      let(:response) do
        {
          'data' => {
            'operation' => { 'id' => operation_id, 'status' => 'complete' },
            'runtime_result' => { 'success' => true, 'data' => { 'status' => 'running' } }
          }
        }
      end

      before do
        allow(api_client).to receive(:post)
          .with("/api/v1/system/worker_api/operations/#{operation_id}/execute")
          .and_return(response)
      end

      it 'returns the response payload' do
        expect(job.execute(operation_id)).to eq(response)
      end
    end

    context 'when the server returns 409 Conflict' do
      let(:api_error) do
        err = BackendApiClient::ApiError.new('Conflict')
        err.define_singleton_method(:status) { 409 }
        err
      end

      before do
        allow(api_client).to receive(:post).and_raise(api_error)
      end

      it 'returns a skipped marker without raising' do
        result = job.execute(operation_id)
        expect(result).to eq(skipped: true, reason: 'already_claimed')
      end
    end

    context 'when the server returns a non-409 API error' do
      let(:api_error) do
        err = BackendApiClient::ApiError.new('Server error')
        err.define_singleton_method(:status) { 500 }
        err
      end

      before do
        allow(api_client).to receive(:post).and_raise(api_error)
      end

      it 'surfaces the error so the reaper can recover' do
        expect { job.execute(operation_id) }.to raise_error(BackendApiClient::ApiError)
      end
    end
  end

  describe 'sidekiq_options' do
    it 'declares retry: 0 to keep the operation state machine authoritative' do
      expect(described_class.get_sidekiq_options['retry']).to eq(0)
    end

    it 'targets the system queue' do
      expect(described_class.get_sidekiq_options['queue']).to eq('system')
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AiWorkflow::ApprovalExpiryJob do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:logger).and_return(Logger.new(nil))
  end

  describe '#execute' do
    context 'when API call is successful' do
      let(:response) do
        {
          success: true,
          data: {
            'expired_count' => 3,
            'failed_executions_count' => 1,
            'affected_execution_ids' => ['node-exec-1']
          }
        }
      end

      before do
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/ai_workflow_approvals/expire_stale')
          .and_return(response)
      end

      it 'calls the expire_stale endpoint' do
        expect(api_client).to receive(:post)
          .with('/api/v1/internal/ai_workflow_approvals/expire_stale')

        job.execute
      end

      it 'returns success with counts' do
        result = job.execute

        expect(result[:success]).to be true
        expect(result[:expired_count]).to eq(3)
        expect(result[:failed_executions_count]).to eq(1)
      end
    end

    context 'when API call fails' do
      let(:response) do
        {
          success: false,
          error: 'Database connection error'
        }
      end

      before do
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/ai_workflow_approvals/expire_stale')
          .and_return(response)
      end

      it 'returns failure with error message' do
        result = job.execute

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Database connection error')
      end
    end

    context 'when API raises an error' do
      before do
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/ai_workflow_approvals/expire_stale')
          .and_raise(BackendApiClient::ApiError.new('Timeout', 504))
      end

      it 'returns failure with error message' do
        result = job.execute

        expect(result[:success]).to be false
        expect(result[:error]).to include('Timeout')
      end
    end

    context 'when no tokens are expired' do
      let(:response) do
        {
          success: true,
          data: {
            'expired_count' => 0,
            'failed_executions_count' => 0,
            'affected_execution_ids' => []
          }
        }
      end

      before do
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/ai_workflow_approvals/expire_stale')
          .and_return(response)
      end

      it 'returns success with zero counts' do
        result = job.execute

        expect(result[:success]).to be true
        expect(result[:expired_count]).to eq(0)
        expect(result[:failed_executions_count]).to eq(0)
      end
    end
  end

  describe 'job configuration' do
    it 'uses the default queue' do
      expect(described_class.sidekiq_options['queue']).to eq('default')
    end

    it 'retries up to 3 times' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end

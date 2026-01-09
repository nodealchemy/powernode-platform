# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::WorkflowRetryStrategyService do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account) }
  let(:node) { create(:ai_workflow_node, workflow: workflow, configuration: default_node_config) }
  let(:default_node_config) do
    {
      'retry' => {
        'enabled' => true,
        'max_retries' => 3,
        'strategy' => 'exponential',
        'initial_delay_ms' => 1000,
        'backoff_multiplier' => 2,
        'max_delay_ms' => 60_000,
        'jitter' => false,
        'retry_on_errors' => %w[timeout rate_limit temporary_failure network_error]
      }
    }
  end
  let(:node_execution) do
    create(:ai_workflow_node_execution,
           workflow_run: workflow_run,
           node: node,
           status: 'failed',
           retry_count: 0,
           metadata: {})
  end

  describe '#retryable?' do
    context 'when retry is enabled and within limits' do
      it 'returns true for retryable error' do
        service = described_class.new(node_execution: node_execution, error_type: 'timeout')
        expect(service.retryable?).to be true
      end
    end

    context 'when retries are disabled' do
      before do
        node.update(configuration: { 'retry' => { 'enabled' => false } })
      end

      it 'returns false' do
        service = described_class.new(node_execution: node_execution, error_type: 'timeout')
        expect(service.retryable?).to be false
      end
    end

    context 'when max retries reached' do
      before do
        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 3 } })
      end

      it 'returns false' do
        service = described_class.new(node_execution: node_execution, error_type: 'timeout')
        expect(service.retryable?).to be false
      end
    end

    context 'when error is not retryable' do
      it 'returns false for non-retryable error' do
        service = described_class.new(node_execution: node_execution, error_type: 'validation_error')
        expect(service.retryable?).to be false
      end
    end
  end

  describe '#calculate_retry_delay' do
    context 'with exponential backoff strategy' do
      before do
        node.update(configuration: {
          'retry' => {
            'enabled' => true,
            'strategy' => 'exponential',
            'initial_delay_ms' => 1000,
            'backoff_multiplier' => 2,
            'max_delay_ms' => 60_000,
            'jitter' => false
          }
        })
      end

      it 'calculates correct delay for first retry' do
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(1000)
      end

      it 'calculates correct delay for second retry' do
        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 1 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(2000)
      end

      it 'calculates correct delay for third retry' do
        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 2 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(4000)
      end

      it 'respects max delay cap' do
        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 10 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(60_000)
      end
    end

    context 'with linear backoff strategy' do
      before do
        node.update(configuration: {
          'retry' => {
            'enabled' => true,
            'strategy' => 'linear',
            'initial_delay_ms' => 1000,
            'linear_increment_ms' => 1000,
            'max_delay_ms' => 60_000,
            'jitter' => false
          }
        })
      end

      it 'calculates correct linear delay' do
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(1000)

        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 1 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(2000)

        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 2 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(3000)
      end
    end

    context 'with fixed backoff strategy' do
      before do
        node.update(configuration: {
          'retry' => {
            'enabled' => true,
            'strategy' => 'fixed',
            'fixed_delay_ms' => 5000,
            'jitter' => false
          }
        })
      end

      it 'returns fixed delay for all retries' do
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(5000)

        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 5 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(5000)
      end
    end

    context 'with custom backoff strategy' do
      before do
        node.update(configuration: {
          'retry' => {
            'enabled' => true,
            'strategy' => 'custom',
            'custom_delays_ms' => [ 1000, 2000, 5000, 10_000 ],
            'jitter' => false
          }
        })
      end

      it 'uses custom delay schedule' do
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(1000)

        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 1 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(2000)

        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 2 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(5000)
      end

      it 'uses last delay when attempts exceed schedule' do
        node_execution.update(metadata: { 'retry' => { 'attempt_count' => 10 } })
        service = described_class.new(node_execution: node_execution)
        expect(service.calculate_retry_delay).to eq(10_000)
      end
    end

    context 'with jitter enabled' do
      before do
        node.update(configuration: {
          'retry' => {
            'enabled' => true,
            'strategy' => 'exponential',
            'initial_delay_ms' => 1000,
            'backoff_multiplier' => 2,
            'jitter' => true
          }
        })
      end

      it 'adds randomization to delay' do
        service = described_class.new(node_execution: node_execution)
        delay = service.calculate_retry_delay

        # Jitter adds ±10%, so delay should be within 900-1100ms
        expect(delay).to be_between(900, 1100)
      end
    end
  end

  describe '#execute_retry' do
    let(:service) { described_class.new(node_execution: node_execution, error_type: 'timeout') }

    before do
      allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
    end

    context 'when retryable' do
      it 'updates retry metadata' do
        expect { service.execute_retry }.to change { node_execution.reload.metadata }
      end

      it 'increments retry attempt count' do
        service.execute_retry
        expect(node_execution.reload.metadata['retry']['attempt_count']).to eq(1)
      end

      it 'records retry timestamp' do
        service.execute_retry
        expect(node_execution.reload.metadata['retry']['last_retry_at']).to be_present
      end

      it 'records delay' do
        service.execute_retry
        expect(node_execution.reload.metadata['retry']['last_delay_ms']).to be_present
      end

      it 'records total retry time' do
        service.execute_retry
        expect(node_execution.reload.metadata['retry']['total_delay_ms']).to be > 0
      end

      it 'records error type' do
        service.execute_retry
        expect(node_execution.reload.metadata['retry']['error_type']).to eq('timeout')
      end

      it 'enqueues worker job' do
        expect(WorkerJobService).to receive(:enqueue_node_execution_retry)
          .with(node_execution.id, hash_including(:delay_ms))

        service.execute_retry
      end

      it 'returns true' do
        expect(service.execute_retry).to be true
      end
    end

    context 'when not retryable' do
      before { node_execution.update(metadata: { 'retry' => { 'attempt_count' => 3 } }) }

      it 'does not enqueue job' do
        expect(WorkerJobService).not_to receive(:enqueue_node_execution_retry)
        service.execute_retry
      end

      it 'returns false' do
        expect(service.execute_retry).to be false
      end
    end
  end

  describe '#retry_stats' do
    let(:service) { described_class.new(node_execution: node_execution, error_type: 'timeout') }

    before do
      node_execution.update(
        retry_count: 2,
        metadata: {
          'retry' => {
            'attempt_count' => 2,
            'total_delay_ms' => 3000,
            'last_retry_at' => 5.seconds.ago.iso8601
          }
        }
      )
    end

    it 'returns comprehensive retry statistics' do
      stats = service.retry_stats

      expect(stats[:current_attempt]).to eq(2)
      expect(stats[:max_retries]).to eq(3)
      expect(stats[:retries_remaining]).to eq(1)
      expect(stats[:total_retry_time_ms]).to eq(3000)
      expect(stats[:last_retry_at]).to be_present
      expect(stats[:error_type]).to eq('timeout')
      expect(stats[:retryable]).to be true
    end

    it 'calculates next retry delay when retryable' do
      stats = service.retry_stats
      expect(stats[:next_retry_delay_ms]).to be_present
    end

    it 'sets next retry delay to nil when not retryable' do
      node_execution.update(metadata: { 'retry' => { 'attempt_count' => 3 } })
      stats = service.retry_stats
      expect(stats[:next_retry_delay_ms]).to be_nil
    end
  end

  describe 'configuration inheritance' do
    context 'with workflow-level configuration' do
      let(:node) { create(:ai_workflow_node, workflow: workflow, configuration: {}) }

      before do
        workflow.update(configuration: {
          'retry' => {
            'enabled' => true,
            'max_retries' => 5,
            'strategy' => 'linear'
          }
        })
      end

      it 'uses workflow configuration when node config absent' do
        service = described_class.new(node_execution: node_execution)
        config = service.retry_config

        expect(config[:max_retries]).to eq(5)
        expect(config[:strategy]).to eq('linear')
      end
    end

    context 'with node-level override' do
      let(:node) do
        create(:ai_workflow_node, workflow: workflow, configuration: {
          'retry' => {
            'enabled' => true,
            'max_retries' => 10,
            'strategy' => 'exponential'
          }
        })
      end

      before do
        workflow.update(configuration: {
          'retry' => {
            'enabled' => true,
            'max_retries' => 5,
            'strategy' => 'linear'
          }
        })
      end

      it 'node configuration overrides workflow configuration' do
        service = described_class.new(node_execution: node_execution)
        config = service.retry_config

        expect(config[:max_retries]).to eq(10)
        expect(config[:strategy]).to eq('exponential')
      end
    end
  end

  describe 'error type classification' do
    it 'retries timeout errors' do
      service = described_class.new(node_execution: node_execution, error_type: 'timeout')
      expect(service.retryable?).to be true
    end

    it 'retries rate limit errors' do
      service = described_class.new(node_execution: node_execution, error_type: 'rate_limit')
      expect(service.retryable?).to be true
    end

    it 'retries temporary failure errors' do
      service = described_class.new(node_execution: node_execution, error_type: 'temporary_failure')
      expect(service.retryable?).to be true
    end

    it 'retries network errors' do
      service = described_class.new(node_execution: node_execution, error_type: 'network_error')
      expect(service.retryable?).to be true
    end

    it 'does not retry validation errors by default' do
      service = described_class.new(node_execution: node_execution, error_type: 'validation_error')
      expect(service.retryable?).to be false
    end

    it 'does not retry permanent errors by default' do
      service = described_class.new(node_execution: node_execution, error_type: 'permanent_failure')
      expect(service.retryable?).to be false
    end
  end
end

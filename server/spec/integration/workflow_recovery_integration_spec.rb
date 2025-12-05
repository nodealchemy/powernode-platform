# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workflow Recovery Integration', type: :integration do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account, version: '1.0.0') }

  before do
    # Clear Redis state
    Redis.current.keys('circuit_breaker:*').each { |key| Redis.current.del(key) }
  end

  describe 'Complete retry and recovery flow' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             ai_workflow: workflow,
             account: account,
             status: 'running',
             input_variables: { 'input_data' => 'test' })
    end

    let(:node) do
      create(:ai_workflow_node,
             ai_workflow: workflow,
             node_type: 'ai_agent',
             configuration: {
               'retry' => {
                 'enabled' => true,
                 'max_retries' => 3,
                 'strategy' => 'exponential',
                 'initial_delay_ms' => 1000,
                 'backoff_multiplier' => 2
               }
             })
    end

    let(:node_execution) do
      create(:ai_workflow_node_execution,
             ai_workflow_run: workflow_run,
             ai_workflow_node: node,
             status: 'failed',
             retry_count: 0,
             max_retries: 3)
    end

    it 'executes complete retry flow' do
      # Step 1: Initial node failure
      retry_service = WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      expect(retry_service.retryable?).to be true

      # Step 2: Calculate retry delay
      delay = retry_service.calculate_retry_delay
      expect(delay).to eq(1000)

      # Step 3: Execute retry
      allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
      result = retry_service.execute_retry

      expect(result).to be true
      expect(node_execution.reload.metadata['retry']['attempt_count']).to eq(1)

      # Step 4: Simulate retry failure and second retry
      node_execution.update(retry_count: 1)
      retry_service2 = WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      delay2 = retry_service2.calculate_retry_delay
      expect(delay2).to eq(2000) # Exponential backoff

      # Step 5: Simulate retries exhausted
      node_execution.update(retry_count: 3)
      retry_service3 = WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      expect(retry_service3.retryable?).to be false
    end

    it 'creates checkpoint during retry process' do
      # Step 1: Create checkpoint before retry
      checkpoint_service = WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      checkpoint = checkpoint_service.create_checkpoint(
        type: 'error_handler',
        node_id: node.id,
        metadata: { reason: 'before_retry' }
      )

      expect(checkpoint).to be_persisted
      expect(checkpoint.checkpoint_type).to eq('error_handler')

      # Step 2: Simulate failed retry
      node_execution.update(status: 'failed')
      workflow_run.update(status: 'failed')

      # Step 3: Verify workflow is recoverable
      expect(WorkflowCheckpointRecoveryService.recoverable?(workflow_run)).to be true

      # Step 4: Find best checkpoint
      best_checkpoint = WorkflowCheckpointRecoveryService.find_recovery_checkpoint(workflow_run)
      expect(best_checkpoint).to eq(checkpoint)

      # Step 5: Restore from checkpoint
      recovery_service = WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: checkpoint
      )

      result = recovery_service.restore_from_checkpoint

      expect(result[:success]).to be true
      expect(workflow_run.reload.status).to eq('running')
    end
  end

  describe 'Circuit breaker integration with retries' do
    it 'opens circuit breaker after multiple failures' do
      service_name = 'ai_provider_anthropic'

      # Step 1: Execute multiple failed requests
      breaker = WorkflowCircuitBreakerManager.get_breaker(service_name)

      5.times do
        begin
          breaker.execute { raise StandardError, 'API timeout' }
        rescue StandardError
          # Expected
        end
      end

      # Step 2: Verify circuit is open
      expect(breaker.state).to eq('open')

      # Step 3: Verify health status
      health = WorkflowCircuitBreakerManager.health_check
      expect(health[service_name][:healthy]).to be false

      # Step 4: Attempt request with open circuit
      expect {
        breaker.execute { 'should not execute' }
      }.to raise_error(AiWorkflowCircuitBreakerService::CircuitOpenError)

      # Step 5: Simulate timeout passing
      Timecop.travel(Time.current + 61) do
        # Circuit should transition to half_open
        breaker.execute { 'success' }

        # After successful execution, should be closed
        expect(breaker.state).to eq('closed')
      end
    end

    it 'coordinates circuit breaker across multiple services' do
      services = %w[ai_provider_anthropic webhook_service external_api]

      # Step 1: Trip multiple circuit breakers
      services.each do |service|
        breaker = WorkflowCircuitBreakerManager.get_breaker(service)
        5.times do
          begin
            breaker.execute { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      # Step 2: Check unhealthy services
      unhealthy = WorkflowCircuitBreakerManager.unhealthy_services
      expect(unhealthy).to contain_exactly(*services)

      # Step 3: Reset specific service
      WorkflowCircuitBreakerManager.reset_service('ai_provider_anthropic')

      # Step 4: Verify only one service reset
      health = WorkflowCircuitBreakerManager.health_check
      expect(health['ai_provider_anthropic'][:state]).to eq('closed')
      expect(health['webhook_service'][:state]).to eq('open')
      expect(health['external_api'][:state]).to eq('open')

      # Step 5: Reset all remaining services
      WorkflowCircuitBreakerManager.reset_all!

      # Step 6: Verify all services healthy
      health_after = WorkflowCircuitBreakerManager.health_check
      health_after.each do |_, data|
        expect(data[:state]).to eq('closed')
        expect(data[:healthy]).to be true
      end
    end
  end

  describe 'End-to-end recovery scenario' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             ai_workflow: workflow,
             account: account,
             status: 'running',
             total_nodes: 5,
             completed_nodes: 0)
    end

    let(:nodes) do
      5.times.map do |i|
        create(:ai_workflow_node,
               ai_workflow: workflow,
               node_id: "node-#{i + 1}",
               node_type: 'ai_agent')
      end
    end

    it 'handles complete workflow failure and recovery' do
      # Step 1: Execute nodes successfully and create checkpoints
      checkpoint_service = WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      nodes[0..2].each_with_index do |node, index|
        node_execution = create(:ai_workflow_node_execution,
                               ai_workflow_run: workflow_run,
                               ai_workflow_node: node,
                               status: 'completed')

        checkpoint = checkpoint_service.create_checkpoint(
          type: 'node_completed',
          node_id: node.node_id
        )

        workflow_run.update(completed_nodes: index + 1)

        expect(checkpoint.sequence_number).to eq(index + 1)
      end

      # Step 2: Simulate failure on node 4
      failing_node = nodes[3]
      failing_execution = create(:ai_workflow_node_execution,
                                 ai_workflow_run: workflow_run,
                                 ai_workflow_node: failing_node,
                                 status: 'failed',
                                 retry_count: 0,
                                 max_retries: 3)

      # Step 3: Attempt retries
      3.times do |attempt|
        retry_service = WorkflowRetryStrategyService.new(
          node_execution: failing_execution,
          error_type: 'temporary_failure'
        )

        if retry_service.retryable?
          allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
          retry_service.execute_retry
          failing_execution.update(retry_count: attempt + 1)
        end
      end

      # Step 4: Mark workflow as failed after retry exhaustion
      workflow_run.update(status: 'failed')

      # Step 5: Verify recovery options
      expect(WorkflowCheckpointRecoveryService.recoverable?(workflow_run)).to be true

      recovery_checkpoint = WorkflowCheckpointRecoveryService.find_recovery_checkpoint(workflow_run)
      expect(recovery_checkpoint).to be_present
      expect(recovery_checkpoint.node_id).to eq('node-3') # Last successful node

      # Step 6: Perform recovery
      recovery_service = WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: recovery_checkpoint
      )

      result = recovery_service.restore_from_checkpoint

      expect(result[:success]).to be true
      expect(result[:resumed_at]).to eq('node-3')
      expect(workflow_run.reload.status).to eq('running')
      expect(workflow_run.runtime_context['recovery_mode']).to be true

      # Step 7: Verify node states
      completed_executions = workflow_run.ai_workflow_node_executions.where(status: 'completed')
      expect(completed_executions.count).to be >= 3
    end

    it 'handles circuit breaker preventing execution' do
      # Step 1: Configure circuit breaker for AI provider
      service_name = 'ai_provider_service'
      breaker = WorkflowCircuitBreakerManager.get_breaker(service_name)

      # Step 2: Trip circuit breaker
      5.times do
        begin
          breaker.execute { raise StandardError, 'Service unavailable' }
        rescue StandardError
          # Expected
        end
      end

      expect(breaker.state).to eq('open')

      # Step 3: Create checkpoint before circuit opens
      checkpoint_service = WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)
      checkpoint = checkpoint_service.create_checkpoint(
        type: 'manual',
        node_id: 'node-2',
        metadata: { reason: 'before_circuit_open' }
      )

      # Step 4: Attempt execution with open circuit
      expect {
        WorkflowCircuitBreakerManager.execute_with_breaker(service_name) do
          'should not execute'
        end
      }.to raise_error(AiWorkflowCircuitBreakerService::CircuitOpenError)

      # Step 5: Mark workflow as failed due to circuit breaker
      workflow_run.update(
        status: 'failed',
        error_details: { error: 'Circuit breaker open', service: service_name }
      )

      # Step 6: Reset circuit breaker
      WorkflowCircuitBreakerManager.reset_service(service_name)

      # Step 7: Restore from checkpoint
      recovery_service = WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: checkpoint
      )

      result = recovery_service.restore_from_checkpoint

      expect(result[:success]).to be true
      expect(workflow_run.reload.status).to eq('running')

      # Step 8: Verify circuit is closed and execution can proceed
      expect(breaker.state).to eq('closed')
      result = WorkflowCircuitBreakerManager.execute_with_breaker(service_name) do
        'successful execution after recovery'
      end
      expect(result).to eq('successful execution after recovery')
    end
  end

  describe 'WebSocket event broadcasting' do
    it 'broadcasts retry events', :focus do
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, account: account)
      node_execution = create(:ai_workflow_node_execution,
                             ai_workflow_run: workflow_run,
                             status: 'failed',
                             retry_count: 0,
                             max_retries: 3)

      # Mock ActionCable broadcast
      expect(ActionCable.server).to receive(:broadcast).with(
        "ai_workflow_run_#{workflow_run.id}",
        hash_including(
          type: 'node_retry_scheduled',
          node_execution_id: node_execution.id
        )
      )

      retry_service = WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
      retry_service.execute_retry
    end

    it 'broadcasts checkpoint events', :focus do
      workflow_run = create(:ai_workflow_run, ai_workflow: workflow, account: account)

      expect(ActionCable.server).to receive(:broadcast).with(
        "ai_workflow_run_#{workflow_run.id}",
        hash_including(
          type: 'checkpoint_created',
          checkpoint_type: 'manual'
        )
      )

      checkpoint_service = WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)
      checkpoint_service.create_checkpoint(type: 'manual', node_id: 'test-node')
    end

    it 'broadcasts circuit breaker events', :focus do
      service_name = 'broadcast_test_service'

      expect(ActionCable.server).to receive(:broadcast).with(
        'ai_monitoring_channel',
        hash_including(
          type: 'circuit_breaker_state_change',
          service: service_name,
          new_state: 'open'
        )
      )

      breaker = WorkflowCircuitBreakerManager.get_breaker(service_name)
      5.times do
        begin
          breaker.execute { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end
  end

  describe 'Recovery statistics and reporting' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             ai_workflow: workflow,
             account: account,
             status: 'failed')
    end

    it 'provides comprehensive recovery statistics' do
      # Create multiple checkpoints
      checkpoint_service = WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      checkpoints = 3.times.map do |i|
        checkpoint_service.create_checkpoint(
          type: 'node_completed',
          node_id: "node-#{i + 1}",
          metadata: { progress_percentage: (i + 1) * 33.3 }
        )
      end

      # Get recovery stats for latest checkpoint
      recovery_service = WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: checkpoints.last
      )

      stats = recovery_service.recovery_stats

      expect(stats).to include(
        checkpoint_id: checkpoints.last.id,
        checkpoint_type: 'node_completed',
        checkpoint_node: 'node-3',
        sequence_number: 3,
        total_checkpoints: 3,
        recoverable: true,
        estimated_resume_position: 99.9
      )
    end

    it 'provides retry statistics' do
      node_execution = create(:ai_workflow_node_execution,
                             ai_workflow_run: workflow_run,
                             status: 'failed',
                             retry_count: 2,
                             max_retries: 3,
                             metadata: {
                               'retry' => {
                                 'attempt_count' => 2,
                                 'total_delay_ms' => 3000
                               }
                             })

      retry_service = WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      stats = retry_service.retry_stats

      expect(stats).to include(
        current_attempt: 2,
        max_retries: 3,
        retries_remaining: 1,
        total_retry_time_ms: 3000,
        error_type: 'timeout',
        retryable: true
      )
    end
  end
end

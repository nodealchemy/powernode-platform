# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workflow Recovery Integration', type: :integration do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account, version: '1.0.0') }

  before do
    # Clear Redis state if Redis is available
    if defined?(Redis) && ENV['REDIS_URL']
      redis = Redis.new(url: ENV['REDIS_URL'])
      redis.keys('circuit_breaker:*').each { |key| redis.del(key) }
      redis.close
    end
  end

  describe 'Complete retry and recovery flow' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             workflow: workflow,
             account: account,
             status: 'running',
             input_variables: { 'input_data' => 'test' })
    end

    let(:node) do
      create(:ai_workflow_node,
             workflow: workflow,
             node_type: 'ai_agent',
             configuration: {
               'retry' => {
                 'enabled' => true,
                 'max_retries' => 3,
                 'strategy' => 'exponential',
                 'initial_delay_ms' => 1000,
                 'backoff_multiplier' => 2,
                 'jitter' => false,
                 'retry_on_errors' => %w[timeout rate_limit temporary_failure network_error]
               }
             })
    end

    let(:node_execution) do
      create(:ai_workflow_node_execution,
             workflow_run: workflow_run,
             node: node,
             status: 'failed',
             retry_count: 0,
             max_retries: 3)
    end

    it 'executes complete retry flow' do
      # Step 1: Initial node failure
      retry_service = Ai::WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      expect(retry_service.retryable?).to be true

      # Step 2: Calculate retry delay (jitter disabled in config)
      delay = retry_service.calculate_retry_delay
      expect(delay).to eq(1000)

      # Step 3: Execute retry
      allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
      result = retry_service.execute_retry

      expect(result).to be true
      expect(node_execution.reload.metadata['retry']['attempt_count']).to eq(1)

      # Step 4: Simulate retry failure and second retry
      node_execution.update(retry_count: 1)
      retry_service2 = Ai::WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      delay2 = retry_service2.calculate_retry_delay
      expect(delay2).to eq(2000) # Exponential backoff (jitter disabled)

      # Step 5: Simulate retries exhausted (update metadata attempt_count to 3)
      node_execution.update(
        retry_count: 3,
        metadata: (node_execution.metadata || {}).merge(
          'retry' => { 'attempt_count' => 3, 'total_delay_ms' => 7000 }
        )
      )
      retry_service3 = Ai::WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      expect(retry_service3.retryable?).to be false
    end

    it 'creates checkpoint during retry process' do
      # Step 1: Create checkpoint before retry (use node_completion which is recoverable)
      checkpoint_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      checkpoint = checkpoint_service.create_checkpoint(
        type: 'node_completion',
        node_id: node.node_id,
        metadata: { reason: 'before_retry' }
      )

      expect(checkpoint).to be_persisted
      expect(checkpoint.checkpoint_type).to eq('node_completion')
      expect(checkpoint.workflow_state).to be_present
      expect(checkpoint.execution_context).to be_present

      # Step 2: Simulate failed retry
      node_execution.update(status: 'failed')
      workflow_run.update(status: 'failed')

      # Step 3: Verify workflow is recoverable
      expect(Ai::WorkflowCheckpointRecoveryService.recoverable?(workflow_run)).to be true

      # Step 4: Find best checkpoint (should find node_completion checkpoint)
      best_checkpoint = Ai::WorkflowCheckpointRecoveryService.find_recovery_checkpoint(workflow_run)
      expect(best_checkpoint).to eq(checkpoint)

      # Step 5: Verify checkpoint can be used for recovery
      expect(checkpoint.can_replay?).to be true

      # Step 6: Initialize recovery service
      recovery_service = Ai::WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: checkpoint
      )

      # Verify recovery stats are available
      stats = recovery_service.recovery_stats
      expect(stats[:recoverable]).to be true
    end
  end

  describe 'Circuit breaker integration with retries' do
    before { Ai::CircuitBreakerRegistry.clear! }

    it 'opens circuit breaker after multiple failures' do
      service_name = 'ai_provider_anthropic'

      # Step 1: Execute multiple failed requests
      breaker = Ai::CircuitBreakerRegistry.get_or_create_breaker(service_name)

      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError, 'API timeout' }
        rescue StandardError
          # Expected
        end
      end

      # Step 2: Verify circuit is open
      expect(breaker.circuit_state).to eq('open')

      # Step 3: Verify health status
      health = Ai::CircuitBreakerRegistry.health_check
      expect(health[service_name][:healthy]).to be false

      # Step 4: Attempt request with open circuit
      expect {
        breaker.execute_with_circuit_breaker { 'should not execute' }
      }.to raise_error(CircuitBreakerCore::CircuitOpenError)

      # Step 5: Simulate timeout passing (use ActiveSupport travel_to)
      travel_to(Time.current + 61.seconds) do
        # Circuit should transition to half_open after first success
        breaker.execute_with_circuit_breaker { 'success' }
        expect(breaker.circuit_state).to eq('half_open')

        # After second successful execution (success_threshold = 2), should be closed
        breaker.execute_with_circuit_breaker { 'success' }
        expect(breaker.circuit_state).to eq('closed')
      end
    end

    it 'coordinates circuit breaker across multiple services' do
      services = %w[ai_provider_anthropic webhook_service external_api]

      # Step 1: Trip multiple circuit breakers
      services.each do |service|
        breaker = Ai::CircuitBreakerRegistry.get_or_create_breaker(service)
        5.times do
          begin
            breaker.execute_with_circuit_breaker { raise StandardError }
          rescue StandardError
            # Expected
          end
        end
      end

      # Step 2: Check unhealthy services
      unhealthy = Ai::CircuitBreakerRegistry.unhealthy_services
      expect(unhealthy).to contain_exactly(*services)

      # Step 3: Reset specific service
      Ai::CircuitBreakerRegistry.reset_service('ai_provider_anthropic')

      # Step 4: Verify only one service reset
      health = Ai::CircuitBreakerRegistry.health_check
      expect(health['ai_provider_anthropic'][:state]).to eq('closed')
      expect(health['webhook_service'][:state]).to eq('open')
      expect(health['external_api'][:state]).to eq('open')

      # Step 5: Reset all remaining services
      Ai::CircuitBreakerRegistry.reset_all!

      # Step 6: Verify all services healthy
      health_after = Ai::CircuitBreakerRegistry.health_check
      health_after.each do |_, data|
        expect(data[:state]).to eq('closed')
        expect(data[:healthy]).to be true
      end
    end
  end

  describe 'End-to-end recovery scenario' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             workflow: workflow,
             account: account,
             status: 'running',
             total_nodes: 5,
             completed_nodes: 0)
    end

    let(:nodes) do
      5.times.map do |i|
        create(:ai_workflow_node,
               workflow: workflow,
               node_id: "node-#{i + 1}",
               node_type: 'ai_agent')
      end
    end

    it 'handles complete workflow failure and recovery' do
      # Step 1: Execute nodes successfully and create checkpoints
      checkpoint_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      nodes[0..2].each_with_index do |node, index|
        node_execution = create(:ai_workflow_node_execution,
                               workflow_run: workflow_run,
                               node: node,
                               status: 'completed')

        checkpoint = checkpoint_service.create_checkpoint(
          type: 'node_completion',
          node_id: node.node_id
        )

        workflow_run.update(completed_nodes: index + 1)

        expect(checkpoint.sequence_number).to eq(index + 1)
      end

      # Step 2: Simulate failure on node 4
      failing_node = nodes[3]
      failing_execution = create(:ai_workflow_node_execution,
                                 workflow_run: workflow_run,
                                 node: failing_node,
                                 status: 'failed',
                                 retry_count: 0,
                                 max_retries: 3)

      # Step 3: Attempt retries
      3.times do |attempt|
        retry_service = Ai::WorkflowRetryStrategyService.new(
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
      expect(Ai::WorkflowCheckpointRecoveryService.recoverable?(workflow_run)).to be true

      recovery_checkpoint = Ai::WorkflowCheckpointRecoveryService.find_recovery_checkpoint(workflow_run)
      expect(recovery_checkpoint).to be_present
      expect(recovery_checkpoint.node_id).to eq('node-3') # Last successful node

      # Step 6: Verify recovery service can be initialized
      recovery_service = Ai::WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: recovery_checkpoint
      )

      # Verify recovery stats are available
      stats = recovery_service.recovery_stats
      expect(stats[:recoverable]).to be true
      expect(stats[:checkpoint_node]).to eq('node-3')
    end

    it 'handles circuit breaker preventing execution' do
      # Step 1: Configure circuit breaker for AI provider
      service_name = 'ai_provider_service'
      breaker = Ai::CircuitBreakerRegistry.get_or_create_breaker(service_name)

      # Step 2: Trip circuit breaker
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError, 'Service unavailable' }
        rescue StandardError
          # Expected
        end
      end

      expect(breaker.circuit_state).to eq('open')

      # Step 3: Create checkpoint before circuit opens
      checkpoint_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)
      checkpoint = checkpoint_service.create_checkpoint(
        type: 'manual_checkpoint',
        node_id: 'node-2',
        metadata: { reason: 'before_circuit_open' }
      )

      # Step 4: Attempt execution with open circuit
      expect {
        Ai::CircuitBreakerRegistry.execute_with_breaker(service_name) do
          'should not execute'
        end
      }.to raise_error(CircuitBreakerCore::CircuitOpenError)

      # Step 5: Mark workflow as failed due to circuit breaker
      workflow_run.update(
        status: 'failed',
        error_details: { error: 'Circuit breaker open', service: service_name }
      )

      # Step 6: Reset circuit breaker
      Ai::CircuitBreakerRegistry.reset_service(service_name)

      # Step 7: Verify circuit is closed and execution can proceed
      expect(breaker.circuit_state).to eq('closed')
      result = Ai::CircuitBreakerRegistry.execute_with_breaker(service_name) do
        'successful execution after recovery'
      end
      expect(result).to eq('successful execution after recovery')

      # Step 8: Verify checkpoint can be used for recovery
      recovery_service = Ai::WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: checkpoint
      )
      stats = recovery_service.recovery_stats
      expect(stats[:checkpoint_id]).to eq(checkpoint.id)
    end
  end

  describe 'WebSocket event broadcasting' do
    it 'broadcasts retry events' do
      workflow_run = create(:ai_workflow_run, workflow: workflow, account: account)

      # Create node with retry enabled
      retry_node = create(:ai_workflow_node,
                          workflow: workflow,
                          node_type: 'ai_agent',
                          configuration: {
                            'retry' => {
                              'enabled' => true,
                              'max_retries' => 3,
                              'jitter' => false,
                              'retry_on_errors' => %w[timeout rate_limit temporary_failure network_error]
                            }
                          })

      node_execution = create(:ai_workflow_node_execution,
                             workflow_run: workflow_run,
                             node: retry_node,
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

      retry_service = Ai::WorkflowRetryStrategyService.new(
        node_execution: node_execution,
        error_type: 'timeout'
      )

      allow(WorkerJobService).to receive(:enqueue_node_execution_retry)
      retry_service.execute_retry
    end

    it 'broadcasts checkpoint events' do
      workflow_run = create(:ai_workflow_run, workflow: workflow, account: account)

      expect(ActionCable.server).to receive(:broadcast).with(
        "ai_workflow_run_#{workflow_run.id}",
        hash_including(
          type: 'checkpoint_created',
          checkpoint_type: 'manual_checkpoint'
        )
      )

      checkpoint_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)
      checkpoint_service.create_checkpoint(type: 'manual_checkpoint', node_id: 'test-node')
    end

    it 'broadcasts circuit breaker events' do
      service_name = 'broadcast_test_service'

      expect(ActionCable.server).to receive(:broadcast).with(
        'ai_monitoring_channel',
        hash_including(
          type: 'circuit_breaker_state_change',
          service: service_name,
          new_state: 'open'
        )
      )

      breaker = Ai::CircuitBreakerRegistry.get_or_create_breaker(service_name)
      5.times do
        begin
          breaker.execute_with_circuit_breaker { raise StandardError }
        rescue StandardError
          # Expected
        end
      end
    end
  end

  describe 'Recovery statistics and reporting' do
    let(:workflow_run) do
      create(:ai_workflow_run,
             workflow: workflow,
             account: account,
             status: 'failed',
             total_nodes: 3)
    end

    it 'provides comprehensive recovery statistics' do
      # Create multiple checkpoints
      checkpoint_service = Ai::WorkflowCheckpointRecoveryService.new(workflow_run: workflow_run)

      checkpoints = 3.times.map do |i|
        # Need to build checkpoint with proper workflow_state
        checkpoint_service.create_checkpoint(
          type: 'node_completion',
          node_id: "node-#{i + 1}",
          metadata: { progress_percentage: (i + 1) * 33.3 }
        )
      end

      # Get the last checkpoint and reload it
      last_checkpoint = checkpoints.last.reload

      # Get recovery stats for latest checkpoint
      recovery_service = Ai::WorkflowCheckpointRecoveryService.new(
        workflow_run: workflow_run,
        checkpoint: last_checkpoint
      )

      stats = recovery_service.recovery_stats

      # Verify core stats are present and correct
      expect(stats[:checkpoint_id]).to eq(last_checkpoint.id)
      expect(stats[:checkpoint_type]).to eq('node_completion')
      expect(stats[:checkpoint_node]).to eq('node-3')
      expect(stats[:sequence_number]).to eq(3)
      expect(stats[:total_checkpoints]).to eq(3)
      expect(stats[:recoverable]).to be true
      expect(stats).to have_key(:estimated_resume_position)
    end

    it 'provides retry statistics' do
      # Create a node with retry enabled
      retry_node = create(:ai_workflow_node,
                          workflow: workflow,
                          node_type: 'ai_agent',
                          configuration: {
                            'retry' => {
                              'enabled' => true,
                              'max_retries' => 3,
                              'retry_on_errors' => %w[timeout rate_limit temporary_failure network_error]
                            }
                          })

      node_execution = create(:ai_workflow_node_execution,
                             workflow_run: workflow_run,
                             node: retry_node,
                             status: 'failed',
                             retry_count: 2,
                             max_retries: 3,
                             metadata: {
                               'retry' => {
                                 'attempt_count' => 2,
                                 'total_delay_ms' => 3000
                               }
                             })

      retry_service = Ai::WorkflowRetryStrategyService.new(
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

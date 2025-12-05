# frozen_string_literal: true

# WorkflowRecoveryService - Advanced workflow recovery and checkpoint management
#
# This service provides high-level coordination for workflow recovery operations,
# acting as a facade that delegates to the MCP checkpoint recovery system.
#
# Key responsibilities:
# - Checkpoint creation and restoration for workflow state
# - Recovery strategy determination and execution
# - Retry logic with exponential backoff
# - Workflow state capture and restoration
# - Error recovery coordination
#
# Architecture:
# - Facade service that coordinates recovery operations
# - Delegates checkpoint management to Mcp::WorkflowCheckpointManager
# - Works alongside Mcp::WorkflowOrchestrator for execution
# - Provides retry strategies and error handling
#
# Recovery Strategies:
# - Checkpoint-based: Restore from last successful checkpoint
# - Node-level retry: Retry failed node with exponential backoff
# - Graceful degradation: Skip failed node and continue
# - Circuit breaker: Prevent cascading failures
#
# @example Create checkpoint and recover
#   recovery = WorkflowRecoveryService.new(workflow_run: run)
#   checkpoint_id = recovery.create_checkpoint(node_id)
#   # ... workflow fails ...
#   recovery.restore_from_checkpoint(checkpoint_id)
#
# @example Retry failed node
#   recovery.retry_with_backoff(node_execution, max_attempts: 5)
#
class WorkflowRecoveryService
  include ActiveModel::Model

  attr_accessor :workflow_run, :account, :user, :logger

  def initialize(workflow_run:, account: nil, user: nil)
    @workflow_run = workflow_run
    @account = account || workflow_run.account
    @user = user || workflow_run.triggered_by_user
    @logger = Rails.logger
    @checkpoints = {}
    @recovery_strategy = determine_recovery_strategy
  end

  # Create a checkpoint for the current workflow state
  def create_checkpoint(node_id = nil, checkpoint_data = {})
    # Delegate to MCP checkpoint manager
    checkpoint_manager.create_checkpoint(node_id, checkpoint_data)
  end

  # Restore workflow from checkpoint
  def restore_from_checkpoint(checkpoint_id = nil)
    # Delegate to MCP checkpoint manager
    success = checkpoint_manager.restore_from_checkpoint(checkpoint_id)

    if success
      # Resume execution from restored checkpoint
      checkpoint = checkpoint_manager.load_checkpoint(checkpoint_id) || checkpoint_manager.find_latest_checkpoint
      resume_from_checkpoint(checkpoint) if checkpoint
    end

    success
  end

  # Implement retry with exponential backoff
  def retry_with_backoff(node_execution, max_attempts: 3, backoff_strategy: :exponential)
    attempt = 0
    delay = 1 # Start with 1 second

    while attempt < max_attempts
      attempt += 1

      @logger.info "[RECOVERY] Retry attempt #{attempt}/#{max_attempts} for node #{node_execution.node_id}"

      begin
        # Retry execution
        result = execute_node_retry(node_execution)

        if result.status == 'completed'
          @logger.info "[RECOVERY] Retry successful for node #{node_execution.node_id}"
          return result
        end

      rescue StandardError => e
        @logger.warn "[RECOVERY] Retry attempt #{attempt} failed: #{e.message}"

        if attempt < max_attempts
          # Calculate backoff delay
          sleep_time = case backoff_strategy
                       when :linear
                         delay * attempt
                       when :exponential
                         delay * (2 ** (attempt - 1))
                       else
                         delay
                       end

          @logger.info "[RECOVERY] Waiting #{sleep_time}s before next retry"
          sleep(sleep_time)
        end
      end
    end

    # All retries exhausted
    @logger.error "[RECOVERY] All retry attempts exhausted for node #{node_execution.node_id}"
    node_execution.tap do |ne|
      ne.update!(status: 'failed') unless ne.status == 'failed'
    end
  end

  # Execute node retry (called by retry_with_backoff)
  def execute_node_retry(node_execution)
    # Reset node execution status
    node_execution.update!(
      status: 'running',
      retry_count: node_execution.retry_count + 1,
      metadata: node_execution.metadata.merge('retry_attempt' => node_execution.retry_count + 1)
    )

    # Execute the node
    execute_node_with_recovery(node_execution)

    # Return the updated node execution
    node_execution.reload
  end

  # Implement circuit breaker pattern
  def with_circuit_breaker(node_id, &block)
    circuit_state = get_circuit_state(node_id)

    case circuit_state[:status]
    when 'open'
      # Circuit is open, don't attempt execution
      @logger.warn "[RECOVERY] Circuit breaker OPEN for node #{node_id}"
      return { success: false, error: 'Circuit breaker is open' }

    when 'half_open'
      # Try execution with caution
      @logger.info "[RECOVERY] Circuit breaker HALF-OPEN for node #{node_id}, attempting execution"

      begin
        result = yield
        if result[:success]
          reset_circuit_breaker(node_id)
        else
          trip_circuit_breaker(node_id)
        end
        result
      rescue StandardError => e
        trip_circuit_breaker(node_id)
        raise e
      end

    else # 'closed'
      # Normal execution
      begin
        result = yield
        record_circuit_success(node_id) if result[:success]
        result
      rescue StandardError => e
        record_circuit_failure(node_id)
        raise e
      end
    end
  end

  # Compensate for failed operations
  def compensate_failure(node_execution)
    @logger.info "[RECOVERY] Executing compensation for failed node #{node_execution.node_id}"

    compensation_strategy = determine_compensation_strategy(node_execution)

    case compensation_strategy
    when :rollback
      rollback_node_effects(node_execution)
    when :compensate
      execute_compensation_logic(node_execution)
    when :skip
      skip_and_continue(node_execution)
    else
      @logger.warn "[RECOVERY] No compensation strategy for node #{node_execution.node_id}"
    end
  end

  # Health check and self-healing
  def perform_health_check
    health_status = {
      workflow_run_id: @workflow_run.id,
      status: @workflow_run.status,
      health_checks: []
    }

    # Check node execution health
    stuck_nodes = find_stuck_nodes
    if stuck_nodes.any?
      health_status[:health_checks] << {
        type: 'stuck_nodes',
        count: stuck_nodes.count,
        nodes: stuck_nodes.map(&:node_id),
        action: 'auto_recovery_initiated'
      }

      # Auto-recover stuck nodes
      stuck_nodes.each { |node| auto_recover_stuck_node(node) }
    end

    # Check for orphaned executions
    orphaned = find_orphaned_executions
    if orphaned.any?
      health_status[:health_checks] << {
        type: 'orphaned_executions',
        count: orphaned.count,
        action: 'cleanup_initiated'
      }

      cleanup_orphaned_executions(orphaned)
    end

    health_status[:healthy] = health_status[:health_checks].empty?
    health_status
  end

  # Apply checkpoint-based recovery strategy
  def apply_checkpoint_recovery_strategy
    @logger.info "[RECOVERY] Applying checkpoint-based recovery strategy"

    # Create checkpoint at current position
    create_checkpoint(@workflow_run.current_node_id, { strategy: 'checkpoint_based' })

    # If workflow failed, restore from last checkpoint
    if @workflow_run.status == 'failed'
      latest_checkpoint = find_latest_checkpoint
      restore_from_checkpoint(latest_checkpoint['id']) if latest_checkpoint
    end
  end

  # Apply node retry recovery strategy
  def apply_node_retry_strategy(node_execution, max_attempts: 3)
    @logger.info "[RECOVERY] Applying node retry strategy for #{node_execution.node_id}"
    retry_with_backoff(node_execution, max_attempts: max_attempts)
  end

  # Apply graceful degradation strategy
  def apply_graceful_degradation(node)
    @logger.info "[RECOVERY] Applying graceful degradation for node #{node.node_id}"

    # Check if node is critical
    is_critical = node.configuration['critical'] == true

    if is_critical
      { action: 'fail_fast', reason: 'Critical node cannot be skipped' }
    else
      # Skip non-critical node
      { action: 'skip', reason: 'Non-critical node skipped to allow workflow continuation' }
    end
  end

  # Mark nodes as completed (for checkpoint restoration)
  def mark_nodes_as_completed(node_ids)
    @logger.info "[RECOVERY] Marking #{node_ids.count} nodes as completed"

    node_ids.each do |node_id|
      # Find existing execution or create with required fields
      node_execution = @workflow_run.ai_workflow_node_executions.find_by(node_id: node_id)

      unless node_execution
        # Need to get the workflow node to create a valid execution
        workflow_node = @workflow_run.ai_workflow.ai_workflow_nodes.find_by(node_id: node_id)
        next unless workflow_node # Skip if node doesn't exist

        node_execution = @workflow_run.ai_workflow_node_executions.create!(
          ai_workflow_node: workflow_node,
          node_id: node_id,
          node_type: workflow_node.node_type,
          execution_id: SecureRandom.uuid,
          status: 'skipped',
          metadata: { 'restored_from_checkpoint' => true }
        )
      else
        node_execution.update!(
          status: 'skipped',
          metadata: node_execution.metadata.merge('restored_from_checkpoint' => true)
        )
      end
    end
  end

  # Find next node to execute after checkpoint
  def find_next_node_after_checkpoint(checkpoint)
    completed_node_ids = checkpoint[:completed_nodes] || checkpoint['completed_nodes']
    current_node_id = checkpoint[:node_id] || checkpoint['node_id']

    # Find the node that follows the checkpoint node
    workflow = @workflow_run.ai_workflow
    workflow_edges = workflow.ai_workflow_edges

    # Find outgoing edges from current node
    next_edge = workflow_edges.find_by(source_node_id: current_node_id)

    return nil unless next_edge

    # Find the target node
    workflow.ai_workflow_nodes.find_by(node_id: next_edge.target_node_id)
  end

  # Execute workflow from specific node
  def execute_workflow_from_node(node_id, variables = {})
    @logger.info "[RECOVERY] Resuming execution from node: #{node_id}"

    # Update runtime context with variables
    @workflow_run.update!(
      runtime_context: @workflow_run.runtime_context.merge('variables' => variables),
      status: 'running'
    )

    # Create orchestrator and continue execution
    orchestrator = Mcp::WorkflowOrchestrator.new(
      workflow_run: @workflow_run,
      account: @account,
      user: @user
    )

    # Execute from specific node
    orchestrator.execute_from_node(node_id)
  end

  private

  # Get or create checkpoint manager instance
  def checkpoint_manager
    @checkpoint_manager ||= Mcp::WorkflowCheckpointManager.new(
      workflow_run: @workflow_run,
      account: @account,
      user: @user,
      logger: @logger
    )
  end

  def determine_recovery_strategy
    # Determine recovery strategy based on workflow run state and duration
    if @workflow_run.started_at && (Time.current - @workflow_run.started_at) > 1.hour
      # Long-running workflows should use checkpoints
      :checkpoint_based
    elsif @workflow_run.status == 'failed' &&
          (@workflow_run.error_details['type'] == 'critical_error' ||
           @workflow_run.error_details['message']&.include?('Critical'))
      # Critical errors need graceful degradation
      :graceful_degradation
    elsif @workflow_run.status == 'failed'
      # Regular failures can use node retry
      :node_retry
    else
      # Default to checkpoint-based for safety
      :checkpoint_based
    end
  end

  def capture_workflow_state
    # Get node execution status counts
    node_statuses = @workflow_run.ai_workflow_node_executions
                                 .group(:status)
                                 .count

    {
      run_status: @workflow_run.status,
      progress: @workflow_run.metadata['progress_percentage'] || 0,
      node_statuses: node_statuses,
      completed_nodes: @workflow_run.completed_nodes,
      failed_nodes: @workflow_run.failed_nodes,
      runtime_context: @workflow_run.runtime_context,
      output_variables: @workflow_run.output_variables,
      node_executions: @workflow_run.ai_workflow_node_executions.map do |ne|
        {
          node_id: ne.node_id,
          status: ne.status,
          output_data: ne.output_data,
          retry_count: ne.retry_count
        }
      end
    }
  end

  def store_checkpoint(checkpoint)
    # Delegate to checkpoint manager (for backward compatibility)
    checkpoint_manager.send(:store_checkpoint, checkpoint)
  end

  def load_checkpoint(checkpoint_id)
    # Delegate to checkpoint manager
    checkpoint_manager.load_checkpoint(checkpoint_id)
  end

  def find_latest_checkpoint
    # Delegate to checkpoint manager
    checkpoint_manager.find_latest_checkpoint
  end

  def restore_workflow_state(checkpoint)
    state = checkpoint[:state] || checkpoint['state']
    variables = checkpoint[:variables] || checkpoint['variables'] || {}
    output_data = checkpoint[:output_data] || checkpoint['output_data'] || {}
    completed_nodes = checkpoint[:completed_nodes] || checkpoint['completed_nodes'] || []

    # Restore workflow run state
    @workflow_run.update!(
      status: 'running', # Resume as running
      runtime_context: @workflow_run.runtime_context.merge('variables' => variables),
      output_variables: @workflow_run.output_variables.merge(output_data)
    )

    # Mark completed nodes
    mark_nodes_as_completed(completed_nodes) if completed_nodes.any?

    # Restore node execution states if present
    if state && state['node_executions']
      state['node_executions'].each do |ne_state|
        node_execution = @workflow_run.ai_workflow_node_executions
          .find_or_create_by(node_id: ne_state['node_id'])

        node_execution.update!(
          status: ne_state['status'],
          output_data: ne_state['output_data'],
          retry_count: ne_state['retry_count']
        )
      end
    end
  end

  def resume_from_checkpoint(checkpoint)
    # Extract checkpoint data (handle both string and symbol keys)
    node_id = checkpoint[:node_id] || checkpoint['node_id']
    variables = checkpoint[:variables] || checkpoint['variables'] || {}

    unless node_id
      @logger.error "[RECOVERY] Cannot resume from checkpoint: missing node_id"
      return false
    end

    @logger.info "[RECOVERY] Resuming execution from node: #{node_id}"

    # Execute workflow from checkpoint node
    execute_workflow_from_node(node_id, variables)
  end

  def execute_node_with_recovery(node_execution)
    executor = AiWorkflowNodeExecutors::AiAgentExecutor.new(
      node_execution: node_execution,
      workflow_run: @workflow_run,
      account: @account,
      user: @user
    )

    executor.execute
  end

  def get_circuit_state(node_id)
    redis_key = "circuit_breaker:#{node_id}"
    state = Rails.cache.read(redis_key) || { status: 'closed', failure_count: 0 }

    # Check if circuit should transition states
    if state[:status] == 'open' && state[:opened_at]
      # Check if enough time has passed to try half-open
      if Time.current - Time.parse(state[:opened_at]) > 30.seconds
        state[:status] = 'half_open'
        Rails.cache.write(redis_key, state, expires_in: 5.minutes)
      end
    end

    state
  end

  def trip_circuit_breaker(node_id)
    @logger.warn "[RECOVERY] Tripping circuit breaker for node #{node_id}"

    state = {
      status: 'open',
      opened_at: Time.current.iso8601,
      failure_count: 0
    }

    Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
  end

  def reset_circuit_breaker(node_id)
    @logger.info "[RECOVERY] Resetting circuit breaker for node #{node_id}"
    Rails.cache.delete("circuit_breaker:#{node_id}")
  end

  def record_circuit_failure(node_id)
    state = get_circuit_state(node_id)
    state[:failure_count] = (state[:failure_count] || 0) + 1

    # Trip circuit if threshold exceeded
    if state[:failure_count] >= 5
      trip_circuit_breaker(node_id)
    else
      Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
    end
  end

  def record_circuit_success(node_id)
    state = get_circuit_state(node_id)
    state[:failure_count] = [0, (state[:failure_count] || 0) - 1].max
    Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
  end

  def determine_compensation_strategy(node_execution)
    config = node_execution.configuration_snapshot

    return config['compensation_strategy'].to_sym if config['compensation_strategy'].present?

    # Default strategies based on node type
    case node_execution.node_type
    when 'transaction'
      :rollback
    when 'external_api'
      :compensate
    else
      :skip
    end
  end

  def rollback_node_effects(node_execution)
    @logger.info "[RECOVERY] Rolling back effects of node #{node_execution.node_id}"

    # Implementation would depend on specific node type
    # For now, mark as rolled back
    node_execution.update!(
      metadata: node_execution.metadata.merge('rolled_back' => true)
    )
  end

  def execute_compensation_logic(node_execution)
    @logger.info "[RECOVERY] Executing compensation logic for node #{node_execution.node_id}"

    # Execute defined compensation logic
    # This would call specific compensation handlers
    node_execution.update!(
      metadata: node_execution.metadata.merge('compensated' => true)
    )
  end

  def skip_and_continue(node_execution)
    @logger.info "[RECOVERY] Skipping failed node #{node_execution.node_id} and continuing"

    node_execution.update!(
      status: 'skipped',
      metadata: node_execution.metadata.merge('skipped_due_to_failure' => true)
    )
  end

  def find_stuck_nodes
    # Find nodes that have been running for too long
    @workflow_run.ai_workflow_node_executions
      .where(status: 'running')
      .where('started_at < ?', 10.minutes.ago)
  end

  def auto_recover_stuck_node(node_execution)
    @logger.info "[RECOVERY] Auto-recovering stuck node #{node_execution.node_id}"

    # Create checkpoint before recovery
    create_checkpoint(node_execution.node_id)

    # Retry the node
    retry_with_backoff(node_execution, 2)
  end

  def find_orphaned_executions
    # Find executions without proper workflow run association
    @workflow_run.ai_workflow_node_executions
      .where(status: %w[pending initializing])
      .where('created_at < ?', 30.minutes.ago)
  end

  def cleanup_orphaned_executions(executions)
    executions.each do |execution|
      @logger.info "[RECOVERY] Cleaning up orphaned execution #{execution.id}"
      execution.update!(
        status: 'cancelled',
        metadata: execution.metadata.merge('cancelled_reason' => 'orphaned_execution')
      )
    end
  end
end
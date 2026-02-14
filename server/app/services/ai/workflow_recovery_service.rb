# frozen_string_literal: true

# Ai::WorkflowRecoveryService - Advanced workflow recovery and checkpoint management
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
# - Works alongside Mcp::AiWorkflowOrchestrator for execution
# - Provides retry strategies and error handling
#
# Recovery Strategies:
# - Checkpoint-based: Restore from last successful checkpoint
# - Node-level retry: Retry failed node with exponential backoff
# - Graceful degradation: Skip failed node and continue
# - Circuit breaker: Prevent cascading failures
#
# @example Create checkpoint and recover
#   recovery = Ai::WorkflowRecoveryService.new(workflow_run: run)
#   checkpoint_id = recovery.create_checkpoint(node_id)
#   # ... workflow fails ...
#   recovery.restore_from_checkpoint(checkpoint_id)
#
# @example Retry failed node
#   recovery.retry_with_backoff(node_execution, max_attempts: 5)
#
class Ai::WorkflowRecoveryService
  include ActiveModel::Model
  include RetryAndCircuitBreaker
  include CheckpointManagement
  include RecoveryStrategies

  attr_accessor :workflow_run, :account, :user, :logger

  def initialize(workflow_run:, account: nil, user: nil)
    @workflow_run = workflow_run
    @account = account || workflow_run.account
    @user = user || workflow_run.triggered_by_user
    @logger = Rails.logger
    @checkpoints = {}
    @recovery_strategy = determine_recovery_strategy
  end
end

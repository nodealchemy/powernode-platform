# frozen_string_literal: true

module Mcp
  #
  # Manages workflow checkpoint creation and restoration for recovery
  #
  # Handles:
  # - Checkpoint creation with workflow state capture
  # - Checkpoint storage in Rails cache (Redis-backed)
  # - Checkpoint restoration for workflow recovery
  # - TTL management for checkpoint expiration
  #
  # @example Create a checkpoint
  #   manager = Mcp::WorkflowCheckpointManager.new(workflow_run: run, account: account, user: user)
  #   checkpoint_id = manager.create_checkpoint('node-123', { step: 1, data: 'value' })
  #
  # @example Restore from checkpoint
  #   manager.restore_from_checkpoint(checkpoint_id) # => true/false
  #
  class WorkflowCheckpointManager
    attr_reader :workflow_run, :account, :user, :logger

    # Initialize checkpoint manager
    #
    # @param workflow_run [AiWorkflowRun] The workflow run to manage checkpoints for
    # @param account [Account] The account context
    # @param user [User] The user context
    # @param logger [Logger] Optional logger (defaults to Rails.logger)
    def initialize(workflow_run:, account:, user:, logger: nil)
      @workflow_run = workflow_run
      @account = account
      @user = user
      @logger = logger || Rails.logger
    end

    # Create a checkpoint at a specific node
    #
    # Captures complete workflow state including:
    # - Current node position
    # - Runtime variables and context
    # - Completed nodes
    # - Output data
    #
    # @param node_id [String, nil] The node ID where checkpoint is created
    # @param checkpoint_data [Hash] Additional checkpoint data
    # @return [String] The checkpoint ID
    def create_checkpoint(node_id = nil, checkpoint_data = {})
      checkpoint_id = SecureRandom.uuid

      checkpoint = {
        "id" => checkpoint_id,
        "workflow_run_id" => @workflow_run.id,
        "node_id" => node_id,
        "created_at" => Time.current.iso8601,
        "state" => capture_workflow_state,
        "data" => checkpoint_data,
        "completed_nodes" => @workflow_run.ai_workflow_node_executions.where(status: "completed").pluck(:node_id),
        "variables" => @workflow_run.runtime_context["variables"] || {},
        "output_data" => @workflow_run.output_variables || {}
      }

      # Store checkpoint in cache with TTL
      store_checkpoint(checkpoint)

      @logger.info "[MCP_CHECKPOINT_MANAGER] Created checkpoint #{checkpoint_id} at node #{node_id}"

      checkpoint_id
    end

    # Restore workflow from a checkpoint
    #
    # Loads checkpoint data and restores workflow state
    #
    # @param checkpoint_id [String, nil] The checkpoint ID to restore (nil loads latest)
    # @return [Boolean] true if restoration successful, false otherwise
    def restore_from_checkpoint(checkpoint_id = nil)
      checkpoint = if checkpoint_id
                     load_checkpoint(checkpoint_id)
      else
                     find_latest_checkpoint
      end

      unless checkpoint
        @logger.warn "[MCP_CHECKPOINT_MANAGER] No checkpoint found for restoration"
        return false
      end

      @logger.info "[MCP_CHECKPOINT_MANAGER] Restoring from checkpoint #{checkpoint['id']}"

      begin
        # Restore workflow state
        restore_workflow_state(checkpoint)

        # Update workflow run with restored state
        @workflow_run.update!(
          runtime_context: @workflow_run.runtime_context.merge(
            "variables" => checkpoint["variables"],
            "restored_from_checkpoint" => checkpoint["id"],
            "restored_at" => Time.current.iso8601
          ),
          metadata: @workflow_run.metadata.merge(
            "restored_from_checkpoint" => checkpoint["id"]
          )
        )

        @logger.info "[MCP_CHECKPOINT_MANAGER] Successfully restored from checkpoint #{checkpoint['id']}"
        true
      rescue StandardError => e
        @logger.error "[MCP_CHECKPOINT_MANAGER] Failed to restore from checkpoint: #{e.message}"
        @logger.error e.backtrace.join("\n")
        false
      end
    end

    # Get checkpoint by ID
    #
    # @param checkpoint_id [String] The checkpoint ID
    # @return [Hash, nil] The checkpoint data or nil if not found
    def load_checkpoint(checkpoint_id)
      Rails.cache.read(checkpoint_cache_key(checkpoint_id))
    end

    # Find the most recent checkpoint for this workflow run
    #
    # @return [Hash, nil] The latest checkpoint or nil if none found
    def find_latest_checkpoint
      # Get all checkpoint keys for this workflow run
      pattern = "workflow_checkpoint:#{@workflow_run.id}:*"

      # Note: This is a simplified implementation
      # In production, you'd want to maintain a sorted set of checkpoints
      # or use a more efficient key structure

      # For now, we'll just try to load from workflow run metadata
      last_checkpoint_id = @workflow_run.metadata&.dig("last_checkpoint_id")
      return nil unless last_checkpoint_id

      load_checkpoint(last_checkpoint_id)
    end

    private

    # Store checkpoint in cache with TTL
    #
    # @param checkpoint [Hash] The checkpoint data
    # @return [Boolean] true if stored successfully
    def store_checkpoint(checkpoint)
      cache_key = checkpoint_cache_key(checkpoint["id"])

      # Store with 24-hour TTL (configurable based on requirements)
      Rails.cache.write(cache_key, checkpoint, expires_in: 24.hours)

      # Also update workflow run metadata with last checkpoint ID
      @workflow_run.update!(
        metadata: @workflow_run.metadata.merge(
          "last_checkpoint_id" => checkpoint["id"],
          "last_checkpoint_at" => checkpoint["created_at"]
        )
      )

      true
    end

    # Generate cache key for checkpoint
    #
    # @param checkpoint_id [String] The checkpoint ID
    # @return [String] The cache key
    def checkpoint_cache_key(checkpoint_id)
      "workflow_checkpoint:#{@workflow_run.id}:#{checkpoint_id}"
    end

    # Capture current workflow state
    #
    # @return [Hash] The captured state
    def capture_workflow_state
      {
        "run_status" => @workflow_run.status,
        "current_node_id" => @workflow_run.current_node_id,
        "execution_mode" => @workflow_run.ai_workflow.configuration&.dig("execution_mode") || "sequential",
        "started_at" => @workflow_run.started_at&.iso8601,
        "runtime_context" => @workflow_run.runtime_context,
        "metadata" => @workflow_run.metadata
      }
    end

    # Restore workflow state from checkpoint
    #
    # @param checkpoint [Hash] The checkpoint data
    # @return [Boolean] true if restoration successful
    def restore_workflow_state(checkpoint)
      state = checkpoint["state"] || {}

      # Mark completed nodes as already executed
      completed_node_ids = checkpoint["completed_nodes"] || []
      mark_nodes_as_completed(completed_node_ids)

      # Restore current node position
      if checkpoint["node_id"]
        @workflow_run.update!(current_node_id: checkpoint["node_id"])
      end

      @logger.info "[MCP_CHECKPOINT_MANAGER] Restored state with #{completed_node_ids.length} completed nodes"
      true
    end

    # Mark nodes as completed in the workflow run
    #
    # @param node_ids [Array<String>] Node IDs to mark as completed
    # @return [void]
    def mark_nodes_as_completed(node_ids)
      return if node_ids.blank?

      node_ids.each do |node_id|
        # Check if execution already exists
        existing_execution = @workflow_run.ai_workflow_node_executions.find_by(node_id: node_id)
        next if existing_execution

        # Create a completed execution record
        node = @workflow_run.ai_workflow.ai_workflow_nodes.find_by(node_id: node_id)
        next unless node

        @workflow_run.ai_workflow_node_executions.create!(
          ai_workflow_node: node,
          node_id: node_id,
          node_type: node.node_type,
          status: "completed",
          started_at: Time.current,
          completed_at: Time.current,
          output_data: { "skipped" => true, "reason" => "restored_from_checkpoint" }
        )
      end
    end
  end
end

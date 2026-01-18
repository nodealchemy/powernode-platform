# frozen_string_literal: true

class AiWorkflowCheckpointRecoveryService
  attr_reader :workflow_run, :checkpoint

  # Checkpoint types (must match model validation)
  CHECKPOINT_TYPES = %w[
    node_completion
    node_start
    workflow_pause
    manual_checkpoint
    error_checkpoint
  ].freeze

  # Checkpoint retention policy (days)
  RETENTION_DAYS = 30

  def initialize(workflow_run:, checkpoint: nil)
    @workflow_run = workflow_run
    @checkpoint = checkpoint
  end

  # Create a checkpoint
  def create_checkpoint(type:, node_id: nil, metadata: {})
    unless CHECKPOINT_TYPES.include?(type)
      raise ArgumentError, "Invalid checkpoint type: #{type}"
    end

    checkpoint_data = build_checkpoint_data(type, node_id, metadata)

    # Create checkpoint record
    new_checkpoint = workflow_run.checkpoints.create!(
      checkpoint_type: type,
      node_id: node_id || "unknown",
      sequence_number: next_sequence_number,
      workflow_state: checkpoint_data[:workflow_state],
      execution_context: checkpoint_data[:execution_context],
      variable_snapshot: checkpoint_data[:variable_snapshot],
      metadata: checkpoint_data[:metadata],
      created_at: Time.current
    )

    Rails.logger.info "[Checkpoint] Created checkpoint #{new_checkpoint.id} for workflow run #{workflow_run.run_id}"

    # Broadcast checkpoint creation event
    broadcast_checkpoint_event(new_checkpoint)

    # Cleanup old checkpoints
    cleanup_old_checkpoints

    new_checkpoint
  rescue StandardError => e
    Rails.logger.error "[Checkpoint] Failed to create checkpoint: #{e.message}"
    raise
  end

  # Restore workflow from checkpoint
  def restore_from_checkpoint
    unless checkpoint
      raise ArgumentError, "No checkpoint provided for restoration"
    end

    Rails.logger.info "[Recovery] Restoring workflow run #{workflow_run.run_id} from checkpoint #{checkpoint.id}"

    transaction_result = ActiveRecord::Base.transaction do
      # 1. Restore variables
      restore_variables

      # 2. Restore runtime context
      restore_runtime_context

      # 3. Restore node execution states
      restore_node_states

      # 4. Update workflow run status
      update_workflow_status

      # 5. Calculate resumed position
      resumed_position = calculate_resume_position

      {
        success: true,
        resumed_at: checkpoint.node_id,
        resumed_position: resumed_position,
        restored_variables: checkpoint.variable_snapshot&.keys || [],
        checkpoint_age_seconds: (Time.current - checkpoint.created_at).to_i
      }
    end

    Rails.logger.info "[Recovery] Successfully restored workflow run #{workflow_run.run_id}"
    transaction_result
  rescue ArgumentError
    raise # Re-raise ArgumentError for validation errors
  rescue StandardError => e
    Rails.logger.error "[Recovery] Failed to restore from checkpoint: #{e.message}"
    { success: false, error: e.message }
  end

  # Find best checkpoint for recovery
  def self.find_recovery_checkpoint(workflow_run)
    # Get all checkpoints ordered by sequence number (most recent first)
    checkpoints = workflow_run.checkpoints
                              .where("created_at > ?", RETENTION_DAYS.days.ago)
                              .order(sequence_number: :desc)

    # Prefer node_completion checkpoints as they represent stable states
    stable_checkpoint = checkpoints.find { |cp| cp.checkpoint_type == "node_completion" }

    # Fall back to most recent checkpoint
    stable_checkpoint || checkpoints.first
  end

  # Check if workflow is recoverable
  def self.recoverable?(workflow_run)
    return false unless workflow_run.failed? || workflow_run.cancelled?

    # Must have at least one checkpoint
    workflow_run.checkpoints.exists?
  end

  # Get recovery statistics
  def recovery_stats
    return {} unless checkpoint

    {
      checkpoint_id: checkpoint.id,
      checkpoint_type: checkpoint.checkpoint_type,
      checkpoint_age_seconds: (Time.current - checkpoint.created_at).to_i,
      checkpoint_node: checkpoint.node_id,
      sequence_number: checkpoint.sequence_number,
      total_checkpoints: workflow_run.checkpoints.count,
      recoverable: self.class.recoverable?(workflow_run),
      estimated_resume_position: calculate_resume_position
    }
  end

  private

  def build_checkpoint_data(type, node_id, metadata)
    {
      workflow_state: {
        status: workflow_run.status,
        completed_nodes: capture_completed_nodes,
        execution_path: capture_execution_path
      },
      execution_context: capture_runtime_context,
      variable_snapshot: capture_current_variables,
      metadata: {
        type: type,
        node_id: node_id,
        workflow_version: workflow_run.workflow.version,
        total_nodes: workflow_run.total_nodes,
        completed_nodes: workflow_run.completed_nodes,
        progress_percentage: calculate_progress_percentage,
        cost_so_far: workflow_run.total_cost,
        duration_so_far: calculate_duration_so_far,
        custom: metadata
      }
    }
  end

  def capture_current_variables
    # Get variables from runtime context
    runtime_vars = workflow_run.runtime_context.dig("variables") || {}

    # Get input variables
    input_vars = workflow_run.input_variables || {}

    # Get output variables from completed nodes
    output_vars = workflow_run.output_variables || {}

    # Merge all variables (output overrides runtime overrides input)
    input_vars.merge(runtime_vars).merge(output_vars)
  end

  def capture_completed_nodes
    workflow_run.node_executions
                .where(status: "completed")
                .pluck(:node_id)
  end

  def capture_runtime_context
    workflow_run.runtime_context || {}
  end

  def capture_execution_path
    workflow_run.node_executions
                .where(status: %w[completed failed])
                .order(:created_at)
                .pluck(:node_id)
  end

  def restore_variables
    variables = checkpoint.variable_snapshot || {}

    # Update runtime context with restored variables
    updated_context = workflow_run.runtime_context.merge(
      "variables" => variables,
      "restored_from_checkpoint" => checkpoint.id,
      "restored_at" => Time.current.iso8601
    )

    workflow_run.update!(
      runtime_context: updated_context,
      output_variables: variables
    )
  end

  def restore_runtime_context
    restored_context = checkpoint.execution_context || {}

    # Merge with current context (preserve variables from restore_variables)
    current_context = workflow_run.runtime_context || {}
    merged_context = current_context.merge(restored_context).merge(
      "restored_from_checkpoint" => checkpoint.id,
      "restored_at" => Time.current.iso8601,
      "recovery_mode" => true
    )

    workflow_run.update!(runtime_context: merged_context)
  end

  def restore_node_states
    completed_nodes = checkpoint.workflow_state["completed_nodes"] || []

    # Mark nodes as completed that were completed at checkpoint
    completed_nodes.each do |node_id|
      # Find the workflow node to get required fields
      workflow_node = workflow_run.workflow.workflow_nodes.find_by(node_id: node_id)
      next unless workflow_node # Skip if node doesn't exist in workflow

      node_execution = workflow_run.node_executions
                                   .find_or_initialize_by(node_id: node_id)

      next if node_execution.completed? # Already marked completed

      # Set required fields for validation
      node_execution.assign_attributes(
        node: workflow_node,
        node_type: workflow_node.node_type,
        status: "completed",
        started_at: checkpoint.created_at,
        completed_at: checkpoint.created_at,
        metadata: (node_execution.metadata || {}).merge(
          "restored_from_checkpoint" => true,
          "checkpoint_id" => checkpoint.id
        )
      )

      node_execution.save!
    end
  end

  def update_workflow_status
    # Reset workflow to running state
    workflow_run.update!(
      status: "running",
      error_details: {},
      metadata: (workflow_run.metadata || {}).merge(
        "recovered_from_checkpoint" => checkpoint.id,
        "recovered_at" => Time.current.iso8601,
        "recovery_sequence" => checkpoint.sequence_number
      )
    )
  end

  def calculate_resume_position
    completed_nodes = checkpoint.workflow_state["completed_nodes"] || []
    total_nodes = workflow_run.total_nodes

    return 0 if total_nodes == 0

    (completed_nodes.length.to_f / total_nodes * 100).round(2)
  end

  def calculate_progress_percentage
    return 0 if workflow_run.total_nodes == 0

    (workflow_run.completed_nodes.to_f / workflow_run.total_nodes * 100).round(2)
  end

  def calculate_duration_so_far
    return 0 unless workflow_run.started_at

    ((Time.current - workflow_run.started_at) * 1000).to_i # milliseconds
  end

  def next_sequence_number
    last_checkpoint = workflow_run.checkpoints
                                  .order(sequence_number: :desc)
                                  .first

    (last_checkpoint&.sequence_number || 0) + 1
  end

  def cleanup_old_checkpoints
    # Keep last N checkpoints and delete older ones
    keep_count = 10 # Keep last 10 checkpoints

    old_checkpoints = workflow_run.checkpoints
                                  .order(sequence_number: :desc)
                                  .offset(keep_count)

    deleted_count = old_checkpoints.destroy_all.count

    if deleted_count > 0
      Rails.logger.info "[Checkpoint] Cleaned up #{deleted_count} old checkpoints for workflow run #{workflow_run.run_id}"
    end
  end

  def broadcast_checkpoint_event(checkpoint)
    ActionCable.server.broadcast(
      "ai_workflow_run_#{workflow_run.id}",
      {
        type: "checkpoint_created",
        checkpoint_id: checkpoint.id,
        checkpoint_type: checkpoint.checkpoint_type,
        node_id: checkpoint.node_id,
        sequence_number: checkpoint.sequence_number,
        timestamp: Time.current.iso8601
      }
    )
  rescue StandardError => e
    Rails.logger.warn "[Checkpoint] Failed to broadcast checkpoint event: #{e.message}"
  end
end

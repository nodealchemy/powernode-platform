# frozen_string_literal: true

class Ai::WorkflowRecoveryService
  module CheckpointManagement
    extend ActiveSupport::Concern

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

    # Apply checkpoint-based recovery strategy
    def apply_checkpoint_recovery_strategy
      @logger.info "[RECOVERY] Applying checkpoint-based recovery strategy"

      # Create checkpoint at current position
      create_checkpoint(@workflow_run.current_node_id, { strategy: "checkpoint_based" })

      # If workflow failed, restore from last checkpoint
      if @workflow_run.status == "failed"
        latest_checkpoint = find_latest_checkpoint
        restore_from_checkpoint(latest_checkpoint["id"]) if latest_checkpoint
      end
    end

    # Mark nodes as completed (for checkpoint restoration)
    def mark_nodes_as_completed(node_ids)
      @logger.info "[RECOVERY] Marking #{node_ids.count} nodes as completed"

      node_ids.each do |node_id|
        # Find existing execution or create with required fields
        node_execution = @workflow_run.node_executions.find_by(node_id: node_id)

        unless node_execution
          # Need to get the workflow node to create a valid execution
          workflow_node = @workflow_run.workflow.nodes.find_by(node_id: node_id)
          next unless workflow_node # Skip if node doesn't exist

          node_execution = @workflow_run.node_executions.create!(
            node: workflow_node,
            node_id: node_id,
            node_type: workflow_node.node_type,
            execution_id: SecureRandom.uuid,
            status: "skipped",
            metadata: { "restored_from_checkpoint" => true }
          )
        else
          node_execution.update!(
            status: "skipped",
            metadata: node_execution.metadata.merge("restored_from_checkpoint" => true)
          )
        end
      end
    end

    # Find next node to execute after checkpoint
    def find_next_node_after_checkpoint(checkpoint)
      completed_node_ids = checkpoint[:completed_nodes] || checkpoint["completed_nodes"]
      current_node_id = checkpoint[:node_id] || checkpoint["node_id"]

      # Find the node that follows the checkpoint node
      workflow = @workflow_run.workflow
      workflow_edges = workflow.edges

      # Find outgoing edges from current node
      next_edge = workflow_edges.find_by(source_node_id: current_node_id)

      return nil unless next_edge

      # Find the target node
      workflow.nodes.find_by(node_id: next_edge.target_node_id)
    end

    # Execute workflow from specific node
    def execute_workflow_from_node(node_id, variables = {})
      @logger.info "[RECOVERY] Resuming execution from node: #{node_id}"

      # Update runtime context with variables
      @workflow_run.update!(
        runtime_context: @workflow_run.runtime_context.merge("variables" => variables),
        status: "running"
      )

      # Create orchestrator and continue execution
      orchestrator = Mcp::AiWorkflowOrchestrator.new(
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

    def find_latest_checkpoint
      # Delegate to checkpoint manager
      checkpoint_manager.find_latest_checkpoint
    end

    def load_checkpoint(checkpoint_id)
      # Delegate to checkpoint manager
      checkpoint_manager.load_checkpoint(checkpoint_id)
    end

    def store_checkpoint(checkpoint)
      # Delegate to checkpoint manager (for backward compatibility)
      checkpoint_manager.send(:store_checkpoint, checkpoint)
    end

    def capture_workflow_state
      # Get node execution status counts
      node_statuses = @workflow_run.node_executions
                                   .group(:status)
                                   .count

      {
        run_status: @workflow_run.status,
        progress: @workflow_run.metadata["progress_percentage"] || 0,
        node_statuses: node_statuses,
        completed_nodes: @workflow_run.completed_nodes,
        failed_nodes: @workflow_run.failed_nodes,
        runtime_context: @workflow_run.runtime_context,
        output_variables: @workflow_run.output_variables,
        node_executions: @workflow_run.node_executions.map do |ne|
          {
            node_id: ne.node_id,
            status: ne.status,
            output_data: ne.output_data,
            retry_count: ne.retry_count
          }
        end
      }
    end

    def restore_workflow_state(checkpoint)
      state = checkpoint[:state] || checkpoint["state"]
      variables = checkpoint[:variables] || checkpoint["variables"] || {}
      output_data = checkpoint[:output_data] || checkpoint["output_data"] || {}
      completed_nodes = checkpoint[:completed_nodes] || checkpoint["completed_nodes"] || []

      # Restore workflow run state
      @workflow_run.update!(
        status: "running", # Resume as running
        runtime_context: @workflow_run.runtime_context.merge("variables" => variables),
        output_variables: @workflow_run.output_variables.merge(output_data)
      )

      # Mark completed nodes
      mark_nodes_as_completed(completed_nodes) if completed_nodes.any?

      # Restore node execution states if present
      if state && state["node_executions"]
        state["node_executions"].each do |ne_state|
          node_execution = @workflow_run.node_executions
            .find_or_create_by(node_id: ne_state["node_id"])

          node_execution.update!(
            status: ne_state["status"],
            output_data: ne_state["output_data"],
            retry_count: ne_state["retry_count"]
          )
        end
      end
    end

    def resume_from_checkpoint(checkpoint)
      # Extract checkpoint data (handle both string and symbol keys)
      node_id = checkpoint[:node_id] || checkpoint["node_id"]
      variables = checkpoint[:variables] || checkpoint["variables"] || {}

      unless node_id
        @logger.error "[RECOVERY] Cannot resume from checkpoint: missing node_id"
        return false
      end

      @logger.info "[RECOVERY] Resuming execution from node: #{node_id}"

      # Execute workflow from checkpoint node
      execute_workflow_from_node(node_id, variables)
    end
  end
end

# frozen_string_literal: true

class Ai::WorkflowRecoveryService
  module RecoveryStrategies
    extend ActiveSupport::Concern

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
          type: "stuck_nodes",
          count: stuck_nodes.count,
          nodes: stuck_nodes.map(&:node_id),
          action: "auto_recovery_initiated"
        }

        # Auto-recover stuck nodes
        stuck_nodes.each { |node| auto_recover_stuck_node(node) }
      end

      # Check for orphaned executions
      orphaned = find_orphaned_executions
      if orphaned.any?
        health_status[:health_checks] << {
          type: "orphaned_executions",
          count: orphaned.count,
          action: "cleanup_initiated"
        }

        cleanup_orphaned_executions(orphaned)
      end

      health_status[:healthy] = health_status[:health_checks].empty?
      health_status
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
      is_critical = node.configuration["critical"] == true

      if is_critical
        { action: "fail_fast", reason: "Critical node cannot be skipped" }
      else
        # Skip non-critical node
        { action: "skip", reason: "Non-critical node skipped to allow workflow continuation" }
      end
    end

    private

    def determine_recovery_strategy
      # Determine recovery strategy based on workflow run state and duration
      if @workflow_run.started_at && (Time.current - @workflow_run.started_at) > 1.hour
        # Long-running workflows should use checkpoints
        :checkpoint_based
      elsif @workflow_run.status == "failed" &&
            (@workflow_run.error_details["type"] == "critical_error" ||
             @workflow_run.error_details["message"]&.include?("Critical"))
        # Critical errors need graceful degradation
        :graceful_degradation
      elsif @workflow_run.status == "failed"
        # Regular failures can use node retry
        :node_retry
      else
        # Default to checkpoint-based for safety
        :checkpoint_based
      end
    end

    def determine_compensation_strategy(node_execution)
      config = node_execution.configuration_snapshot

      return config["compensation_strategy"].to_sym if config["compensation_strategy"].present?

      # Default strategies based on node type
      case node_execution.node_type
      when "transaction"
        :rollback
      when "external_api"
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
        metadata: node_execution.metadata.merge("rolled_back" => true)
      )
    end

    def execute_compensation_logic(node_execution)
      @logger.info "[RECOVERY] Executing compensation logic for node #{node_execution.node_id}"

      # Execute defined compensation logic
      # This would call specific compensation handlers
      node_execution.update!(
        metadata: node_execution.metadata.merge("compensated" => true)
      )
    end

    def skip_and_continue(node_execution)
      @logger.info "[RECOVERY] Skipping failed node #{node_execution.node_id} and continuing"

      node_execution.update!(
        status: "skipped",
        metadata: node_execution.metadata.merge("skipped_due_to_failure" => true)
      )
    end

    def find_stuck_nodes
      # Find nodes that have been running for too long
      @workflow_run.node_executions
        .where(status: "running")
        .where("started_at < ?", 10.minutes.ago)
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
      @workflow_run.node_executions
        .where(status: %w[pending initializing])
        .where("created_at < ?", 30.minutes.ago)
    end

    def cleanup_orphaned_executions(executions)
      executions.each do |execution|
        @logger.info "[RECOVERY] Cleaning up orphaned execution #{execution.id}"
        execution.update!(
          status: "cancelled",
          metadata: execution.metadata.merge("cancelled_reason" => "orphaned_execution")
        )
      end
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
  end
end

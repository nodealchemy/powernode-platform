# frozen_string_literal: true

module Orchestration
  module WorkflowControl
    def pause_execution(run)
      unless run.status == "running"
        raise StandardError, "Cannot pause workflow run in status: #{run.status}"
      end

      checkpoint_data = {
        execution_state: "paused",
        paused_at: Time.current.iso8601,
        current_node_executions: run.node_executions
                                    .where(status: %w[pending running])
                                    .pluck(:id, :node_id, :status),
        runtime_context: run.runtime_context
      }

      run.update!(
        status: "waiting_approval",
        metadata: (run.metadata || {}).merge("checkpoint_data" => checkpoint_data)
      )

      @logger.info "Paused workflow run #{run.run_id}"
    end

    def resume_execution(run)
      unless run.status == "waiting_approval" && run.metadata&.dig("checkpoint_data", "execution_state") == "paused"
        raise StandardError, "Cannot resume workflow run that is not paused. Current status: #{run.status}"
      end

      run.update!(
        status: "running",
        metadata: (run.metadata || {}).merge("resumed_at" => Time.current.iso8601)
      )

      checkpoint_data = run.metadata&.dig("checkpoint_data")
      if checkpoint_data.present?
        execute_from_checkpoint(checkpoint_data)
      end

      @logger.info "Resumed workflow run #{run.run_id}"
    end

    def cancel_execution(run, reason: nil)
      run.node_executions
         .where(status: %w[pending running])
         .update_all(
           status: "cancelled",
           completed_at: Time.current,
           error_details: { cancellation_reason: reason || "Workflow execution cancelled" }.to_json
         )

      run.cancel_execution!(reason || "Workflow execution cancelled")

      log_workflow_event(run, "workflow_cancelled", {
        reason: reason || "Manual cancellation",
        cancelled_at: Time.current.iso8601
      })

      @logger.info "Cancelled workflow run #{run.run_id}#{reason ? " - #{reason}" : ''}"
    end

    private

    def execute_from_checkpoint(checkpoint_data)
      execution_state = checkpoint_data["execution_state"]
      current_executions = checkpoint_data["current_node_executions"] || []

      @logger.info "Restoring execution from checkpoint: #{execution_state}"

      current_executions.each do |exec_data|
        node_id = exec_data[1]
        status = exec_data[2]

        if status == "running"
          @logger.info "Resuming execution for node #{node_id}"
        end
      end
    end

    def log_workflow_event(run, event_type, data = {})
      @logger.info "Workflow Event [#{run.run_id}] #{event_type}: #{data}"
    end
  end
end

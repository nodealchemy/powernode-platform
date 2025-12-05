# frozen_string_literal: true

class UpdateEventTypeConstraint < ActiveRecord::Migration[8.0]
  def up
    # Drop the existing constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_run_logs
      DROP CONSTRAINT ai_workflow_run_logs_event_type_check;
    SQL

    # Add the updated constraint with all the new event types
    execute <<-SQL
      ALTER TABLE ai_workflow_run_logs
      ADD CONSTRAINT ai_workflow_run_logs_event_type_check
      CHECK (event_type IN (
        'workflow_started', 'workflow_completed', 'workflow_failed', 'workflow_cancelled',
        'node_started', 'node_completed', 'node_failed', 'node_cancelled', 'node_skipped',
        'variable_updated', 'condition_evaluated', 'error_handled', 'retry_attempted',
        'approval_requested', 'approval_granted', 'approval_denied',
        'webhook_sent', 'api_called', 'data_transformed',
        'cost_added', 'timeout_detected',
        'ai_agent_execution_queued', 'api_call_queued', 'webhook_queued',
        'condition_evaluation_queued', 'loop_execution_queued', 'transform_execution_queued',
        'sub_workflow_queued', 'merge_execution_queued', 'split_execution_queued',
        'delay_scheduled', 'node_retry_scheduled',
        'webhook_started', 'webhook_sending', 'webhook_response_received', 'webhook_completed', 'webhook_failed',
        'condition_evaluation_started', 'condition_evaluation_completed', 'condition_evaluation_error',
        'node_execution_error', 'delay_execution_started', 'delay_execution_completed',
        'approval_notification_sent', 'merge_execution_started', 'merge_execution_completed',
        'split_execution_started', 'split_execution_completed', 'api_call_started',
        'api_request_sent', 'api_response_received', 'api_call_completed', 'api_call_failed',
        'human_approval_started', 'human_approval_initiated', 'approval_request_created',
        'approval_email_sent', 'approval_in_app_sent'
      ));
    SQL
  end

  def down
    # Drop the new constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_run_logs
      DROP CONSTRAINT ai_workflow_run_logs_event_type_check;
    SQL

    # Restore the original constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_run_logs
      ADD CONSTRAINT ai_workflow_run_logs_event_type_check
      CHECK (event_type IN (
        'workflow_started', 'workflow_completed', 'workflow_failed', 'workflow_cancelled',
        'node_started', 'node_completed', 'node_failed', 'node_cancelled', 'node_skipped',
        'variable_updated', 'condition_evaluated', 'error_handled', 'retry_attempted',
        'approval_requested', 'approval_granted', 'approval_denied',
        'webhook_sent', 'api_called', 'data_transformed'
      ));
    SQL
  end
end

# frozen_string_literal: true

# Add waiting_approval status to step executions
# This status indicates the step is paused awaiting user approval
class AddWaitingApprovalStatusToStepExecutions < ActiveRecord::Migration[8.0]
  def up
    # Fix any inconsistent status values first
    execute <<-SQL
      UPDATE ci_cd_step_executions SET status = 'failure' WHERE status = 'failed';
    SQL

    # Check if there's an existing constraint on status
    constraint_exists = execute(<<-SQL).any?
      SELECT 1 FROM pg_constraint
      WHERE conname LIKE '%step_executions%status%'
      AND conrelid = 'ci_cd_step_executions'::regclass
    SQL

    # Remove old constraint if it exists
    if constraint_exists
      execute <<-SQL
        ALTER TABLE ci_cd_step_executions
        DROP CONSTRAINT IF EXISTS ci_cd_step_executions_status_check;
      SQL
    end

    # Add new constraint with waiting_approval status
    execute <<-SQL
      ALTER TABLE ci_cd_step_executions
      ADD CONSTRAINT ci_cd_step_executions_status_check
      CHECK (status IN ('pending', 'running', 'waiting_approval', 'success', 'failure', 'skipped'));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE ci_cd_step_executions
      DROP CONSTRAINT IF EXISTS ci_cd_step_executions_status_check;
    SQL

    # Restore original constraint without waiting_approval
    execute <<-SQL
      ALTER TABLE ci_cd_step_executions
      ADD CONSTRAINT ci_cd_step_executions_status_check
      CHECK (status IN ('pending', 'running', 'success', 'failure', 'skipped'));
    SQL
  end
end

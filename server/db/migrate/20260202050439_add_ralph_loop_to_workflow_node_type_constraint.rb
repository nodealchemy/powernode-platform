# frozen_string_literal: true

class AddRalphLoopToWorkflowNodeTypeConstraint < ActiveRecord::Migration[8.1]
  def up
    # Remove old constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Add updated constraint with ralph_loop
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN (
        'start', 'end', 'trigger',
        'ai_agent', 'prompt_template', 'data_processor', 'transform',
        'condition', 'loop', 'delay', 'merge', 'split',
        'database', 'file', 'validator',
        'email', 'notification',
        'api_call', 'webhook', 'scheduler',
        'human_approval', 'sub_workflow',
        'kb_article', 'page', 'mcp_operation',
        'ci_trigger', 'ci_wait_status', 'ci_get_logs', 'ci_cancel',
        'git_commit_status', 'git_create_check',
        'integration_execute',
        'git_checkout', 'git_branch', 'git_pull_request', 'git_comment',
        'deploy', 'run_tests', 'shell_command',
        'ralph_loop'
      ));
    SQL
  end

  def down
    # Remove new constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Restore old constraint without ralph_loop
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN (
        'start', 'end', 'trigger',
        'ai_agent', 'prompt_template', 'data_processor', 'transform',
        'condition', 'loop', 'delay', 'merge', 'split',
        'database', 'file', 'validator',
        'email', 'notification',
        'api_call', 'webhook', 'scheduler',
        'human_approval', 'sub_workflow',
        'kb_article', 'page', 'mcp_operation',
        'ci_trigger', 'ci_wait_status', 'ci_get_logs', 'ci_cancel',
        'git_commit_status', 'git_create_check',
        'integration_execute',
        'git_checkout', 'git_branch', 'git_pull_request', 'git_comment',
        'deploy', 'run_tests', 'shell_command'
      ));
    SQL
  end
end

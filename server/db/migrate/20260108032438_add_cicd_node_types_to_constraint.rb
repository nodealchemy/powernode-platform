# frozen_string_literal: true

class AddCicdNodeTypesToConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove old constraint
    execute <<~SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Add updated constraint with all 38 node types (matching AiWorkflowNode::VALID_NODE_TYPES)
    execute <<~SQL
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

  def down
    # Revert to original constraint (without CI/CD types)
    execute <<~SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    execute <<~SQL
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
        'git_commit_status', 'git_create_check'
      ));
    SQL
  end
end

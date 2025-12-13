# frozen_string_literal: true

class AddTriggerToNodeTypeConstraint < ActiveRecord::Migration[8.0]
  def up
    # Remove the old constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Add the new constraint with 'trigger' included
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN ('start', 'end', 'trigger', 'ai_agent', 'api_call', 'webhook',
                           'condition', 'loop', 'transform', 'delay', 'human_approval',
                           'sub_workflow', 'merge', 'split'));
    SQL
  end

  def down
    # Remove the updated constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Restore the old constraint without 'trigger'
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN ('start', 'end', 'ai_agent', 'api_call', 'webhook',
                           'condition', 'loop', 'transform', 'delay', 'human_approval',
                           'sub_workflow', 'merge', 'split'));
    SQL
  end
end

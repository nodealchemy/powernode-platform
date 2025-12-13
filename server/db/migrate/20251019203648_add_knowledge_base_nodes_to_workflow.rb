# frozen_string_literal: true

class AddKnowledgeBaseNodesToWorkflow < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Add the updated constraint with knowledge base and page management node types
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN (
        -- Core Flow Nodes
        'start', 'end', 'trigger',
        -- AI & Processing Nodes
        'ai_agent', 'prompt_template', 'data_processor', 'transform',
        -- Control Flow Nodes
        'condition', 'loop', 'delay', 'merge', 'split',
        -- Data Operations Nodes
        'database', 'file', 'validator',
        -- Communication Nodes
        'email', 'notification',
        -- Integration Nodes
        'api_call', 'webhook', 'scheduler',
        -- Process Nodes
        'human_approval', 'sub_workflow',
        -- Knowledge Base Article Management
        'kb_article_create', 'kb_article_read', 'kb_article_update',
        'kb_article_search', 'kb_article_publish',
        -- Page Content Management
        'page_create', 'page_read', 'page_update', 'page_publish'
      ));
    SQL
  end

  def down
    # Remove the updated constraint
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      DROP CONSTRAINT IF EXISTS ai_workflow_nodes_type_check;
    SQL

    # Restore the old constraint without knowledge base node types
    execute <<-SQL
      ALTER TABLE ai_workflow_nodes
      ADD CONSTRAINT ai_workflow_nodes_type_check
      CHECK (node_type IN ('start', 'end', 'trigger', 'ai_agent', 'api_call', 'webhook',
                           'condition', 'loop', 'transform', 'delay', 'human_approval',
                           'sub_workflow', 'merge', 'split'));
    SQL
  end
end

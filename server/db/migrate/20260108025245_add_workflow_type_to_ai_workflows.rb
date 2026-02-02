# frozen_string_literal: true

class AddWorkflowTypeToAiWorkflows < ActiveRecord::Migration[8.0]
  def up
    # Add workflow_type column to distinguish between AI workflows and CI/CD pipelines
    # Valid values: 'ai' (default, AI automation workflows), 'cicd' (CI/CD pipelines)
    add_column :ai_workflows, :workflow_type, :string, limit: 20, default: "ai", null: false

    # Add check constraint for valid workflow types
    add_check_constraint :ai_workflows,
      "workflow_type IN ('ai', 'cicd')",
      name: "ai_workflows_workflow_type_check"

    # Add index for workflow type filtering
    add_index :ai_workflows, :workflow_type, name: "index_ai_workflows_on_workflow_type"

    # Composite index for account + type filtering
    add_index :ai_workflows, [ :account_id, :workflow_type ], name: "index_ai_workflows_on_account_id_and_workflow_type"
  end

  def down
    remove_index :ai_workflows, name: "index_ai_workflows_on_account_id_and_workflow_type"
    remove_index :ai_workflows, name: "index_ai_workflows_on_workflow_type"
    remove_check_constraint :ai_workflows, name: "ai_workflows_workflow_type_check"
    remove_column :ai_workflows, :workflow_type
  end
end

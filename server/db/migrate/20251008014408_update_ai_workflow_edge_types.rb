# frozen_string_literal: true

class UpdateAiWorkflowEdgeTypes < ActiveRecord::Migration[7.1]
  def up
    # Remove old check constraint
    remove_check_constraint :ai_workflow_edges, name: 'ai_workflow_edges_type_check'

    # Add new check constraint with expanded edge types
    # Aligned with industry standards from AWS Step Functions, Azure Logic Apps, Apache Airflow
    add_check_constraint :ai_workflow_edges,
      "edge_type IN ('default', 'success', 'error', 'conditional', 'retry', 'timeout', 'skip', 'fallback', 'compensation', 'loop')",
      name: 'ai_workflow_edges_type_check'
  end

  def down
    # Rollback: restore original constraint
    remove_check_constraint :ai_workflow_edges, name: 'ai_workflow_edges_type_check'

    add_check_constraint :ai_workflow_edges,
      "edge_type IN ('default', 'success', 'error', 'conditional', 'loop')",
      name: 'ai_workflow_edges_type_check'
  end
end

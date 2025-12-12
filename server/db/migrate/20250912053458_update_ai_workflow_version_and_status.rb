# frozen_string_literal: true

class UpdateAiWorkflowVersionAndStatus < ActiveRecord::Migration[8.0]
  def up
    # Remove the existing status constraint
    remove_check_constraint :ai_workflows, name: 'ai_workflows_status_check'

    # Change version column from integer to string
    change_column :ai_workflows, :version, :string, null: false, default: '1.0.0'

    # Update existing integer versions to semantic version format
    execute <<~SQL
      UPDATE ai_workflows SET version = version || '.0.0' WHERE version IS NOT NULL
    SQL

    # Add the updated status constraint with new values
    add_check_constraint :ai_workflows,
      "status IN ('draft', 'active', 'paused', 'inactive', 'archived')",
      name: 'ai_workflows_status_check'
  end

  def down
    # Remove the new status constraint
    remove_check_constraint :ai_workflows, name: 'ai_workflows_status_check'

    # Change version back to integer
    change_column :ai_workflows, :version, :integer, null: false, default: 1

    # Add back the original status constraint
    add_check_constraint :ai_workflows,
      "status IN ('draft', 'published', 'archived', 'paused')",
      name: 'ai_workflows_status_check'
  end
end

# frozen_string_literal: true

class AddAccountOwnershipToAiWorkflowTemplates < ActiveRecord::Migration[8.0]
  def change
    add_reference :ai_workflow_templates, :account, type: :uuid, foreign_key: true, null: true
    add_reference :ai_workflow_templates, :created_by_user, type: :uuid, foreign_key: { to_table: :users }, null: true

    add_index :ai_workflow_templates, [:account_id, :is_public]
  end
end

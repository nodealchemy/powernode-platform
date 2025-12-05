# frozen_string_literal: true

class AddVersioningToAiWorkflows < ActiveRecord::Migration[8.0]
  def change
    # version column already exists, just add missing columns
    add_column :ai_workflows, :parent_version_id, :uuid, null: true
    add_column :ai_workflows, :is_active, :boolean, null: false, default: true
    add_column :ai_workflows, :change_summary, :text
    add_column :ai_workflows, :version_metadata, :jsonb, default: {}

    add_index :ai_workflows, :version unless index_exists?(:ai_workflows, :version)
    add_index :ai_workflows, :parent_version_id
    add_index :ai_workflows, :is_active
    add_index :ai_workflows, [:account_id, :name, :version], unique: true, name: 'index_workflows_on_account_name_version'

    add_foreign_key :ai_workflows, :ai_workflows, column: :parent_version_id, on_delete: :nullify
  end
end

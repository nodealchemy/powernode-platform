# frozen_string_literal: true

class CreateGitWorkflowTriggers < ActiveRecord::Migration[8.0]
  def change
    create_table :git_workflow_triggers, id: :uuid do |t|
      # Primary associations
      t.references :ai_workflow_trigger, null: false, foreign_key: true, type: :uuid, index: true
      t.references :git_repository, null: true, foreign_key: true, type: :uuid, index: true

      # Git event configuration
      t.string :event_type, null: false
      t.string :branch_pattern, default: '*'
      t.string :path_pattern
      t.jsonb :event_filters, null: false, default: {}

      # Payload mapping (git event fields -> workflow variables)
      t.jsonb :payload_mapping, null: false, default: {}

      # Status and settings
      t.boolean :is_active, null: false, default: true
      t.string :status, null: false, default: 'active'

      # Metrics
      t.integer :trigger_count, null: false, default: 0
      t.timestamp :last_triggered_at

      # Metadata
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # Indexes for efficient querying
    add_index :git_workflow_triggers, :event_type
    add_index :git_workflow_triggers, :is_active
    add_index :git_workflow_triggers, :status
    add_index :git_workflow_triggers, [:event_type, :is_active],
              name: 'index_git_workflow_triggers_on_event_type_active'
    add_index :git_workflow_triggers, [:git_repository_id, :event_type],
              name: 'index_git_workflow_triggers_on_repo_and_event'
  end
end

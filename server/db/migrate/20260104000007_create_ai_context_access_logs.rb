# frozen_string_literal: true

class CreateAiContextAccessLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_context_access_logs, id: :uuid do |t|
      # Relationships
      t.references :ai_persistent_context, null: false, foreign_key: true, type: :uuid
      t.references :ai_context_entry, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :user, foreign_key: true, type: :uuid
      t.references :ai_agent, foreign_key: true, type: :uuid

      # Access Details
      t.string :action, null: false  # read, write, update, delete, search, export, import
      t.string :access_type  # user, agent, workflow, api, system

      # Request Information
      t.string :request_id
      t.string :ip_address
      t.string :user_agent

      # Change Tracking (for write operations)
      t.jsonb :previous_value
      t.jsonb :new_value
      t.jsonb :changes_summary, default: {}

      # Metadata
      t.jsonb :metadata, default: {}

      # Result
      t.boolean :success, default: true
      t.text :error_message

      t.timestamps
    end

    add_index :ai_context_access_logs, :action
    add_index :ai_context_access_logs, :access_type
    add_index :ai_context_access_logs, :success
    add_index :ai_context_access_logs, [:ai_persistent_context_id, :action], name: "idx_access_logs_context_action"
    add_index :ai_context_access_logs, [:account_id, :created_at], name: "idx_access_logs_account_created"
  end
end

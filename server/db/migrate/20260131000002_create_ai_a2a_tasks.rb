# frozen_string_literal: true

class CreateAiA2aTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_a2a_tasks, id: :uuid do |t|
      # A2A Protocol Task Identity
      t.string :task_id, null: false  # A2A-compliant task ID for external reference

      # Relationships
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :from_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.references :to_agent, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.references :from_agent_card, foreign_key: { to_table: :ai_agent_cards }, type: :uuid
      t.references :to_agent_card, foreign_key: { to_table: :ai_agent_cards }, type: :uuid
      t.references :ai_workflow_run, foreign_key: true, type: :uuid
      t.references :parent_task, foreign_key: { to_table: :ai_a2a_tasks }, type: :uuid

      # A2A Task State
      t.string :status, default: "pending", null: false  # pending, active, completed, failed, cancelled, input_required

      # A2A Message Content
      t.jsonb :message, default: {}, null: false  # role, parts (text, file, data)
      t.jsonb :input, default: {}, null: false    # Legacy/simplified input format
      t.jsonb :output, default: {}, null: false   # Legacy/simplified output format
      t.jsonb :artifacts, default: [], null: false  # Files, data produced {id, name, mimeType, uri, parts}

      # A2A Push Notification Config
      t.jsonb :push_notification_config, default: {}  # url, token, authentication

      # A2A History & Context
      t.jsonb :history, default: [], null: false  # Array of message objects for context
      t.jsonb :metadata, default: {}, null: false

      # Error Handling
      t.text :error_message
      t.string :error_code
      t.jsonb :error_details, default: {}

      # Execution Tracking
      t.integer :sequence_number  # Within workflow run
      t.integer :retry_count, default: 0, null: false
      t.integer :max_retries, default: 3, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_ms

      # Cost Tracking
      t.decimal :cost, precision: 12, scale: 6, default: 0
      t.integer :tokens_used, default: 0

      # External A2A
      t.boolean :is_external, default: false, null: false
      t.string :external_endpoint_url
      t.jsonb :external_authentication, default: {}

      t.timestamps
    end

    add_index :ai_a2a_tasks, :task_id, unique: true
    add_index :ai_a2a_tasks, [:account_id, :status]
    add_index :ai_a2a_tasks, [:from_agent_id, :status]
    add_index :ai_a2a_tasks, [:to_agent_id, :status]
    add_index :ai_a2a_tasks, [:ai_workflow_run_id, :sequence_number]
    add_index :ai_a2a_tasks, :created_at
    add_index :ai_a2a_tasks, :is_external

    add_check_constraint :ai_a2a_tasks,
      "status IN ('pending', 'active', 'completed', 'failed', 'cancelled', 'input_required')",
      name: "ai_a2a_tasks_status_check"
  end
end

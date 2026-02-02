# frozen_string_literal: true

class CreateAiA2aTaskEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_a2a_task_events, id: :uuid do |t|
      # Relationships
      t.references :ai_a2a_task, null: false, foreign_key: true, type: :uuid

      # A2A Event Information
      t.string :event_type, null: false  # status_change, artifact_added, message, progress, error
      t.string :event_id  # A2A streaming event ID

      # Event Content
      t.jsonb :data, default: {}, null: false
      t.text :message

      # State Changes
      t.string :previous_status
      t.string :new_status

      # Progress Tracking (for streaming)
      t.integer :progress_current
      t.integer :progress_total
      t.string :progress_message

      # Artifact Reference
      t.string :artifact_id
      t.string :artifact_name
      t.string :artifact_mime_type

      t.timestamps
    end

    add_index :ai_a2a_task_events, [ :ai_a2a_task_id, :created_at ], name: "idx_a2a_events_task_time"
    add_index :ai_a2a_task_events, :event_type
    add_index :ai_a2a_task_events, :event_id

    add_check_constraint :ai_a2a_task_events,
      "event_type IN ('status_change', 'artifact_added', 'message', 'progress', 'error', 'cancelled')",
      name: "ai_a2a_task_events_type_check"
  end
end

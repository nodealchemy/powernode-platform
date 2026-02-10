# frozen_string_literal: true

class CreateAiAguiSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agui_sessions, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, foreign_key: true, index: true
      t.uuid :agent_id
      t.string :thread_id, null: false
      t.string :run_id
      t.string :parent_run_id
      t.string :status, null: false, default: "idle"
      t.jsonb :state, default: {}
      t.jsonb :messages, default: []
      t.jsonb :tools, default: []
      t.jsonb :context, default: []
      t.jsonb :capabilities, default: {}
      t.integer :sequence_number, default: 0, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_event_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :ai_agui_sessions, :thread_id
    add_index :ai_agui_sessions, :status
    add_index :ai_agui_sessions, :expires_at
  end
end

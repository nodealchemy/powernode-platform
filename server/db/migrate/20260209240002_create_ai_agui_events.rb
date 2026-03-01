# frozen_string_literal: true

class CreateAiAguiEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agui_events, id: :uuid do |t|
      t.references :session, type: :uuid, null: false, foreign_key: { to_table: :ai_agui_sessions }, index: true
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :event_type, null: false
      t.integer :sequence_number, null: false
      t.string :message_id
      t.string :tool_call_id
      t.string :role
      t.text :content
      t.jsonb :delta, default: {}
      t.jsonb :metadata, default: {}
      t.string :run_id
      t.string :step_id
      t.timestamps
    end

    add_index :ai_agui_events, :event_type
    add_index :ai_agui_events, [:session_id, :sequence_number], unique: true
  end
end

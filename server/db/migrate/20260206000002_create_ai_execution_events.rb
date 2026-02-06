# frozen_string_literal: true

class CreateAiExecutionEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_execution_events, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false
      t.jsonb :metadata, default: {}
      t.decimal :cost_usd, precision: 10, scale: 6
      t.integer :duration_ms
      t.string :error_class
      t.text :error_message

      t.timestamps
    end

    add_index :ai_execution_events, [:source_type, :source_id]
    add_index :ai_execution_events, [:account_id, :created_at]
    add_index :ai_execution_events, [:event_type, :status]
    add_index :ai_execution_events, :created_at
  end
end

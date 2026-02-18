# frozen_string_literal: true

class CreateAiTelemetryEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_telemetry_events, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :event_category, null: false
      t.string :event_type, null: false
      t.integer :sequence_number, null: false, default: 0
      t.uuid :parent_event_id
      t.string :correlation_id, null: false
      t.jsonb :event_data, null: false, default: {}
      t.string :outcome

      t.timestamps
    end

    add_index :ai_telemetry_events, [:agent_id, :event_category, :created_at],
              name: "idx_ai_telemetry_events_agent_cat_time"
    add_index :ai_telemetry_events, :correlation_id,
              name: "idx_ai_telemetry_events_correlation"
    add_index :ai_telemetry_events, :parent_event_id,
              name: "idx_ai_telemetry_events_parent"
    add_index :ai_telemetry_events, [:account_id, :created_at],
              name: "idx_ai_telemetry_events_account_time"
  end
end

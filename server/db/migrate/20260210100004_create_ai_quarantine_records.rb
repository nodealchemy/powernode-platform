# frozen_string_literal: true

class CreateAiQuarantineRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_quarantine_records, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.uuid :agent_id, null: false
      t.string :severity, null: false
      t.string :status, null: false, default: "active"
      t.string :trigger_reason, null: false
      t.string :trigger_source
      t.jsonb :restrictions_applied, default: {}
      t.jsonb :forensic_snapshot, default: {}
      t.jsonb :previous_capabilities, default: {}
      t.uuid :escalated_from_id
      t.uuid :approved_by_id
      t.datetime :restored_at
      t.datetime :scheduled_restore_at
      t.integer :cooldown_minutes, default: 60
      t.text :restoration_notes
      t.timestamps
    end

    add_index :ai_quarantine_records, :agent_id
    add_index :ai_quarantine_records, :severity
    add_index :ai_quarantine_records, :status
    add_index :ai_quarantine_records, :scheduled_restore_at
  end
end

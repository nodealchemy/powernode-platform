# frozen_string_literal: true

class CreateAiPressureFields < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_pressure_fields, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true

      t.string :field_type, null: false
      t.string :artifact_type
      t.string :artifact_ref, null: false
      t.decimal :pressure_value, precision: 5, scale: 4, default: 0.0, null: false
      t.decimal :decay_rate, precision: 5, scale: 4, default: 0.02, null: false
      t.decimal :threshold, precision: 5, scale: 4, default: 0.5, null: false
      t.jsonb :dimensions, default: {}
      t.datetime :last_measured_at
      t.datetime :last_addressed_at
      t.uuid :last_addressed_by_id
      t.integer :address_count, default: 0, null: false

      t.timestamps
    end

    add_index :ai_pressure_fields, [:account_id, :field_type, :artifact_ref],
              unique: true, name: "idx_pressure_fields_unique"
    add_index :ai_pressure_fields, [:account_id, :field_type], name: "idx_pressure_fields_type"
    add_index :ai_pressure_fields, :pressure_value
  end
end

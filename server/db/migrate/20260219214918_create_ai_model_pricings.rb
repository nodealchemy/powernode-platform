# frozen_string_literal: true

class CreateAiModelPricings < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_model_pricings, id: :uuid do |t|
      t.string :model_id, null: false
      t.string :provider_type, null: false
      t.decimal :input_per_1k, precision: 12, scale: 8, null: false
      t.decimal :output_per_1k, precision: 12, scale: 8, null: false
      t.decimal :cached_input_per_1k, precision: 12, scale: 8, default: 0
      t.string :tier
      t.string :source, null: false # litellm, manual, constant_fallback
      t.datetime :last_synced_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_model_pricings, [:model_id, :provider_type], unique: true
    add_index :ai_model_pricings, :provider_type
    add_index :ai_model_pricings, :source
  end
end

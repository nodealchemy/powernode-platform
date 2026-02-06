# frozen_string_literal: true

class CreateAiGuardrailConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_guardrail_configs, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :ai_agent, null: true, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.boolean :is_active, null: false, default: true
      t.jsonb :input_rails, null: false, default: []
      t.jsonb :output_rails, null: false, default: []
      t.jsonb :retrieval_rails, null: false, default: []
      t.jsonb :configuration, null: false, default: {}
      t.integer :max_input_tokens, default: 100_000
      t.integer :max_output_tokens, default: 50_000
      t.decimal :toxicity_threshold, precision: 3, scale: 2, default: 0.7
      t.decimal :pii_sensitivity, precision: 3, scale: 2, default: 0.8
      t.boolean :block_on_failure, null: false, default: false
      t.integer :total_checks, null: false, default: 0
      t.integer :total_blocks, null: false, default: 0
      t.timestamps
    end

    add_index :ai_guardrail_configs, [:account_id, :name], unique: true
  end
end

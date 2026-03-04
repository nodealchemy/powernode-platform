# frozen_string_literal: true

class CreateAiStigmergicSignals < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_stigmergic_signals, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :emitter_agent, type: :uuid, foreign_key: { to_table: :ai_agents }
      t.references :memory_pool, type: :uuid, foreign_key: { to_table: :ai_memory_pools }

      t.string :signal_type, null: false
      t.string :signal_key, null: false
      t.decimal :strength, precision: 5, scale: 4, default: 1.0, null: false
      t.decimal :decay_rate, precision: 5, scale: 4, default: 0.05, null: false
      t.jsonb :payload, default: {}
      t.jsonb :reinforcements, default: []
      t.integer :perceive_count, default: 0, null: false
      t.integer :reinforce_count, default: 0, null: false
      t.datetime :expires_at

      t.timestamps
    end

    add_index :ai_stigmergic_signals, [:account_id, :signal_type], name: "idx_stigmergic_signals_type"
    add_index :ai_stigmergic_signals, [:account_id, :signal_key], name: "idx_stigmergic_signals_key"
    add_index :ai_stigmergic_signals, :strength
    add_index :ai_stigmergic_signals, :expires_at, where: "expires_at IS NOT NULL"
  end
end

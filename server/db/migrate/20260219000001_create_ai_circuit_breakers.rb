# frozen_string_literal: true

class CreateAiCircuitBreakers < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_circuit_breakers, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :action_type, null: false
      t.string :state, null: false, default: "closed"
      t.integer :failure_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :failure_threshold, null: false, default: 5
      t.integer :success_threshold, null: false, default: 3
      t.integer :cooldown_seconds, null: false, default: 300
      t.datetime :last_failure_at
      t.datetime :last_success_at
      t.datetime :opened_at
      t.datetime :half_opened_at
      t.jsonb :history, null: false, default: []

      t.timestamps
    end

    add_index :ai_circuit_breakers, [:agent_id, :action_type], unique: true
    add_index :ai_circuit_breakers, [:account_id, :state]

    add_check_constraint :ai_circuit_breakers,
      "state IN ('closed', 'open', 'half_open')",
      name: "check_circuit_breaker_state"
  end
end

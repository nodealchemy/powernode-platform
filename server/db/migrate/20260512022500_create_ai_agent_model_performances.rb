# frozen_string_literal: true

class CreateAiAgentModelPerformances < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_agent_model_performances, id: :uuid do |t|
      t.references :account,      type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.references :ai_provider,  type: :uuid, null: false, foreign_key: { to_table: :ai_providers }
      t.string  :model,        null: false, limit: 120
      t.string  :agent_type,   null: false, limit: 50

      t.integer :total_runs,        null: false, default: 0
      t.integer :successful_runs,   null: false, default: 0
      t.integer :failed_runs,       null: false, default: 0

      t.decimal :total_cost_usd,    null: false, default: 0, precision: 14, scale: 6
      t.bigint  :total_duration_ms, null: false, default: 0
      t.bigint  :total_tokens,      null: false, default: 0

      t.datetime :last_run_at
      t.timestamps
    end

    add_index :ai_agent_model_performances,
              %i[account_id ai_provider_id model agent_type],
              unique: true,
              name: "idx_ai_agent_model_perf_lookup"
  end
end

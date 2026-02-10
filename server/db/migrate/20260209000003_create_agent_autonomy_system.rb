# frozen_string_literal: true

class CreateAgentAutonomySystem < ActiveRecord::Migration[8.0]
  def change
    # Agent lineage - parent/child spawn tracking
    create_table :ai_agent_lineages, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :parent_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :child_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.string :spawn_reason
      t.datetime :spawned_at
      t.datetime :terminated_at
      t.string :termination_reason
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    # Agent trust scores - multi-dimensional trust tracking
    create_table :ai_agent_trust_scores, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }, index: { unique: true }
      t.decimal :reliability, precision: 5, scale: 4, default: 0.5
      t.decimal :cost_efficiency, precision: 5, scale: 4, default: 0.5
      t.decimal :safety, precision: 5, scale: 4, default: 1.0
      t.decimal :quality, precision: 5, scale: 4, default: 0.5
      t.decimal :speed, precision: 5, scale: 4, default: 0.5
      t.decimal :overall_score, precision: 5, scale: 4, default: 0.5
      t.string :tier, default: "supervised"
      t.datetime :last_evaluated_at
      t.integer :evaluation_count, default: 0
      t.jsonb :evaluation_history, default: []
      t.timestamps
    end

    # Agent budgets - hierarchical budget tracking
    create_table :ai_agent_budgets, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.uuid :parent_budget_id
      t.integer :total_budget_cents, null: false
      t.integer :spent_cents, default: 0
      t.integer :reserved_cents, default: 0
      t.string :currency, default: "USD"
      t.string :period_type
      t.datetime :period_start
      t.datetime :period_end
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_foreign_key :ai_agent_budgets, :ai_agent_budgets, column: :parent_budget_id

    # Add autonomy fields to existing ai_agents table
    add_column :ai_agents, :parent_agent_id, :uuid
    add_column :ai_agents, :trust_level, :string, default: "supervised"
    add_column :ai_agents, :termination_policy, :string, default: "graceful"
    add_column :ai_agents, :max_spawn_depth, :integer, default: 3
    add_column :ai_agents, :autonomy_config, :jsonb, default: {}

    add_index :ai_agents, :parent_agent_id
  end
end

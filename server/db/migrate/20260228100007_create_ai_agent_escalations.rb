# frozen_string_literal: true

class CreateAiAgentEscalations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_escalations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :ai_agent, type: :uuid, null: false, foreign_key: { to_table: :ai_agents }
      t.references :escalated_to_user, type: :uuid, foreign_key: { to_table: :users }

      t.string :escalation_type, null: false
      t.string :severity, null: false, default: "medium"
      t.string :status, null: false, default: "open"
      t.string :title, null: false
      t.jsonb :context, default: {}
      t.jsonb :escalation_chain, default: []
      t.integer :current_level, null: false, default: 0
      t.integer :timeout_hours
      t.datetime :next_escalation_at
      t.datetime :acknowledged_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :ai_agent_escalations, :status
    add_index :ai_agent_escalations, :severity
    add_index :ai_agent_escalations, [:account_id, :status]
    add_index :ai_agent_escalations, :next_escalation_at,
              where: "status IN ('open', 'acknowledged', 'in_progress')",
              name: "idx_ai_agent_escalations_due"
  end
end

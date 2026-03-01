# frozen_string_literal: true

class CreateAiShadowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_shadow_executions, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid
      t.string :action_type, null: false
      t.jsonb :shadow_input, null: false, default: {}
      t.jsonb :shadow_output, null: false, default: {}
      t.jsonb :reference_output, default: {}
      t.boolean :agreed, null: false, default: false
      t.float :agreement_score, null: false, default: 0.0

      t.timestamps
    end

    add_index :ai_shadow_executions, [:account_id, :agent_id, :created_at],
              name: "idx_ai_shadow_executions_account_agent_time"
    add_index :ai_shadow_executions, [:agent_id, :agreed],
              name: "idx_ai_shadow_executions_agent_agreed"
  end
end

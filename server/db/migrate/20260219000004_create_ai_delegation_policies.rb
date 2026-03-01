# frozen_string_literal: true

class CreateAiDelegationPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_delegation_policies, id: :uuid do |t|
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :agent, null: false, foreign_key: { to_table: :ai_agents }, type: :uuid, index: { unique: true }
      t.integer :max_depth, null: false, default: 3
      t.jsonb :allowed_delegate_types, null: false, default: []
      t.jsonb :delegatable_actions, null: false, default: []
      t.float :budget_delegation_pct, null: false, default: 0.5
      t.string :inheritance_policy, null: false, default: "conservative"

      t.timestamps
    end

    add_index :ai_delegation_policies, [:account_id, :agent_id],
              name: "idx_ai_delegation_policies_account_agent"

    add_check_constraint :ai_delegation_policies,
      "inheritance_policy IN ('conservative', 'moderate', 'permissive')",
      name: "check_delegation_inheritance_policy"
  end
end

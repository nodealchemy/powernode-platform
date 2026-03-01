# frozen_string_literal: true

class CreateAiAgentPrivilegePolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_agent_privilege_policies, id: :uuid do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.uuid :agent_id
      t.string :policy_name, null: false
      t.string :policy_type, null: false, default: "custom"
      t.string :trust_tier
      t.jsonb :allowed_actions, default: []
      t.jsonb :denied_actions, default: []
      t.jsonb :allowed_tools, default: []
      t.jsonb :denied_tools, default: []
      t.jsonb :allowed_resources, default: []
      t.jsonb :denied_resources, default: []
      t.jsonb :communication_rules, default: {}
      t.jsonb :escalation_rules, default: {}
      t.integer :priority, default: 0
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :ai_agent_privilege_policies, :agent_id
    add_index :ai_agent_privilege_policies, :policy_type
    add_index :ai_agent_privilege_policies, :trust_tier
    add_index :ai_agent_privilege_policies, [:account_id, :policy_name], unique: true
  end
end

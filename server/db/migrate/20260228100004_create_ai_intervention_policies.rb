# frozen_string_literal: true

class CreateAiInterventionPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_intervention_policies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :account, type: :uuid, null: false, foreign_key: true, index: true
      t.references :user, type: :uuid, foreign_key: true
      t.references :ai_agent, type: :uuid, foreign_key: true
      t.string :scope, null: false, default: "global"
      t.string :action_category, null: false
      t.string :policy, null: false
      t.jsonb :conditions, default: {}
      t.jsonb :preferred_channels, default: []
      t.integer :priority, null: false, default: 0
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :ai_intervention_policies, [:account_id, :scope]
    add_index :ai_intervention_policies, [:account_id, :user_id, :ai_agent_id],
              name: "idx_ai_intervention_policies_specificity"
    add_index :ai_intervention_policies, [:account_id, :action_category]
  end
end

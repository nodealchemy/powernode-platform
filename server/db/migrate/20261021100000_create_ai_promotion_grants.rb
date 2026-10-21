# frozen_string_literal: true

# Time-boxed promotion grants (Ai::PromotionGrant): a person's standing,
# narrow permission for ONE agent to perform ONE gated category into ONE
# environment, optionally only for some modules, at most N times, until a time
# at most 24 hours after issue. Ai::AutonomyGate consumes a matching grant in
# place of parking. The operation that ran under a grant points at it.
class CreateAiPromotionGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_promotion_grants, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :granted_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      # A grant names one agent and one plane; it goes when either does.
      t.references :ai_agent, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :environment, null: false, type: :uuid, foreign_key: { to_table: :ai_environments, on_delete: :cascade }
      t.references :revoked_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :action_category, null: false
      # Empty means any module. A uuid array, not JSON: the gate matches one id.
      t.uuid :module_ids, array: true, null: false, default: []
      t.integer :max_uses
      # When true, the grant is spent only when its granter is the person
      # driving the agent's call; by default anyone who can drive the agent can.
      t.boolean :granter_driven_only, null: false, default: false
      t.integer :uses_count, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.text :reason, null: false
      t.timestamps
    end

    # The gate's lookup: this account's grants for one agent and category.
    add_index :ai_promotion_grants, %i[account_id ai_agent_id action_category expires_at],
              name: "idx_ai_promotion_grants_lookup"
    add_check_constraint :ai_promotion_grants, "uses_count >= 0", name: "chk_ai_promotion_grants_uses_nonnegative"
    add_check_constraint :ai_promotion_grants, "max_uses IS NULL OR (max_uses > 0 AND uses_count <= max_uses)",
                         name: "chk_ai_promotion_grants_within_max_uses"

    add_reference :ai_deferred_operations, :promotion_grant, type: :uuid, index: true,
                  foreign_key: { to_table: :ai_promotion_grants, on_delete: :nullify }
  end
end

# frozen_string_literal: true

# Agent-requested promotion grants (Ai::PromotionGrantRequest). An agent asks
# for a grant with frozen terms; the request parks as a human-only approval
# card; a person approves it in their own session and the grant is issued in
# that person's name with exactly those terms.
#
# A grant (and the request that asked for it) may be BOUND to one target: the
# requester's MCP session or the Platform Developer run (Ai::AgentExecution)
# making the call. A bound grant is spent only by a call carrying that target,
# and only while it is live. binding_id is polymorphic over the two kinds, so
# it carries no foreign key; both columns are set or neither is.
class CreateAiPromotionGrantRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_promotion_grant_requests, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :account, null: false, type: :uuid, foreign_key: true
      # The agent asking, for itself only. A request goes when its agent does.
      t.references :ai_agent, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :environment, null: false, type: :uuid, foreign_key: { to_table: :ai_environments, on_delete: :cascade }
      # The person driving the requesting call, when known (attribution only).
      t.references :requested_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      # The person whose own-session approval issued (or was refused) the grant.
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :promotion_grant, type: :uuid, foreign_key: { to_table: :ai_promotion_grants, on_delete: :nullify }
      t.references :approval_request, type: :uuid, foreign_key: { to_table: :ai_approval_requests, on_delete: :nullify }
      # The frozen terms (Ai::PromotionGrant::TERMS less the two only issue
      # fixes: granted_by is the approver, expires_at counts from approval).
      t.string :action_category, null: false
      t.uuid :module_ids, array: true, null: false, default: []
      t.integer :max_uses
      t.integer :lifetime_seconds, null: false
      t.text :reason, null: false
      t.boolean :granter_driven_only, null: false, default: false
      t.string :binding_kind
      t.uuid :binding_id
      t.string :call_origin
      t.string :status, null: false, default: "pending"
      t.text :refusal_reason
      t.datetime :decided_at
      t.timestamps
    end

    add_check_constraint :ai_promotion_grant_requests,
                         "status IN ('pending', 'issued', 'refused', 'rejected', 'expired', 'cancelled')",
                         name: "chk_ai_promotion_grant_requests_status"
    add_check_constraint :ai_promotion_grant_requests, "lifetime_seconds > 0",
                         name: "chk_ai_promotion_grant_requests_lifetime_positive"
    add_check_constraint :ai_promotion_grant_requests, "max_uses IS NULL OR max_uses > 0",
                         name: "chk_ai_promotion_grant_requests_max_uses_positive"
    add_check_constraint :ai_promotion_grant_requests,
                         "(binding_kind IS NULL AND binding_id IS NULL) OR " \
                         "(binding_kind IN ('mcp_session', 'agent_execution') AND binding_id IS NOT NULL)",
                         name: "chk_ai_promotion_grant_requests_binding_pair"
    # One open request per agent, plane and category: a second ask is the first one.
    add_index :ai_promotion_grant_requests, %i[ai_agent_id environment_id action_category],
              unique: true, where: "status = 'pending'", name: "idx_ai_promotion_grant_requests_one_pending"

    add_column :ai_promotion_grants, :binding_kind, :string
    add_column :ai_promotion_grants, :binding_id, :uuid
    add_check_constraint :ai_promotion_grants,
                         "(binding_kind IS NULL AND binding_id IS NULL) OR " \
                         "(binding_kind IN ('mcp_session', 'agent_execution') AND binding_id IS NOT NULL)",
                         name: "chk_ai_promotion_grants_binding_pair"
    add_index :ai_promotion_grants, %i[binding_kind binding_id]
  end
end

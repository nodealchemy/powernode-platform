# frozen_string_literal: true

# HIER-P0 — Ai::DelegationPolicy uniqueness becomes (agent_id, account_id).
#
# The table and its REST surface were account-scoped from the start, but the
# schema carried a UNIQUE index on agent_id alone (and the model validated the
# same). Under the canonical rule — official agents are GLOBAL seeded rows
# (account_id NULL) and account agents are clones — two accounts customising
# the same canonical agent's delegation authority collided on the second
# write, and a canonical (account-less) policy row was impossible because
# account_id was NOT NULL.
#
# Same shape as ai_agents' slug indexes: one partial unique index for account
# rows and one for global rows, because a plain composite unique index treats
# every NULL as distinct and would let a global row be inserted twice.
class ScopeDelegationPolicyUniquenessToAccount < ActiveRecord::Migration[8.1]
  def up
    change_column_null :ai_delegation_policies, :account_id, true

    remove_index :ai_delegation_policies, name: "index_ai_delegation_policies_on_agent_id"
    # Superseded by the unique (agent_id, account_id) partial index below;
    # account-only lookups keep index_ai_delegation_policies_on_account_id.
    remove_index :ai_delegation_policies, name: "index_ai_delegation_policies_on_account_id_and_agent_id"

    add_index :ai_delegation_policies, [ :agent_id, :account_id ],
              unique: true, where: "account_id IS NOT NULL",
              name: "index_ai_delegation_policies_on_agent_id_and_account_id"
    add_index :ai_delegation_policies, :agent_id,
              unique: true, where: "account_id IS NULL",
              name: "index_ai_delegation_policies_on_agent_id_global"
  end

  def down
    # A global row cannot survive NOT NULL, and a second per-agent row cannot
    # survive the restored unique index on agent_id alone. Both would have to
    # be DELETED — a canonical policy row and every account's customisation of
    # a shared agent except one, irrecoverably. That is a decision an operator
    # makes, not a side effect of `db:rollback`, so the rollback refuses while
    # any such row exists.
    doomed = select_value(<<~SQL).to_i
      SELECT (SELECT COUNT(*) FROM ai_delegation_policies WHERE account_id IS NULL)
           + (SELECT COUNT(*) - COUNT(DISTINCT agent_id)
                FROM ai_delegation_policies WHERE account_id IS NOT NULL)
    SQL

    if doomed.positive? && !ENV["ALLOW_DELEGATION_POLICY_DATA_LOSS"].to_s.casecmp("true").zero?
      raise ActiveRecord::IrreversibleMigration,
            "Rolling back would DELETE #{doomed} ai_delegation_policies row(s) " \
            "(canonical global rows and per-agent duplicates across accounts) to fit the " \
            "restored unique index on agent_id. Re-run with " \
            "ALLOW_DELEGATION_POLICY_DATA_LOSS=true once that loss is intended."
    end

    remove_index :ai_delegation_policies, name: "index_ai_delegation_policies_on_agent_id_global"
    remove_index :ai_delegation_policies, name: "index_ai_delegation_policies_on_agent_id_and_account_id"

    execute "DELETE FROM ai_delegation_policies WHERE account_id IS NULL"
    execute <<~SQL
      DELETE FROM ai_delegation_policies p
      USING ai_delegation_policies q
      WHERE p.agent_id = q.agent_id AND p.id > q.id
    SQL

    add_index :ai_delegation_policies, [ :account_id, :agent_id ],
              name: "index_ai_delegation_policies_on_account_id_and_agent_id"
    add_index :ai_delegation_policies, :agent_id, unique: true,
              name: "index_ai_delegation_policies_on_agent_id"
    change_column_null :ai_delegation_policies, :account_id, false
  end
end

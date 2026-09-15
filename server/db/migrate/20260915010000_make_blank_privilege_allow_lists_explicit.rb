# frozen_string_literal: true

# IMP-636a10c80024. Ai::AgentPrivilegePolicy#action_allowed?, #tool_allowed?
# and #resource_allowed? now read a blank (empty or null) allow-list as DENY
# (operator rule 2026-09-08: a blank permission list means deny). Every row
# written before meant "unrestricted, bounded by the deny-list" by the same
# bytes, so each blank allow-list is rewritten to the explicit wildcard rather
# than letting the new reading silently revoke it.
#
# "Blank" means what the old model's `.empty?` answered true for: [], {} and
# "". NULL (SQL or JSON null) is deliberately NOT rewritten: the old model
# raised on it and PrivilegeEnforcementService failed closed, so it already
# denied and still does.
class MakeBlankPrivilegeAllowListsExplicit < ActiveRecord::Migration[8.1]
  COLUMNS = %w[allowed_actions allowed_tools allowed_resources].freeze

  def up
    COLUMNS.each do |column|
      execute <<~SQL.squish
        UPDATE ai_agent_privilege_policies
           SET #{column} = '["*"]'::jsonb, updated_at = NOW()
         WHERE #{column} IN ('[]'::jsonb, '{}'::jsonb, '""'::jsonb)
      SQL
    end
  end

  # A repaired row cannot be told apart from one written ["*"] on purpose.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

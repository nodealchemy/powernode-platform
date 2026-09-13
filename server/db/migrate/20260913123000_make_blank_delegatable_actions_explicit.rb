# frozen_string_literal: true

# IMP-d2873a16567e. Ai::DelegationPolicy#allows_action? now reads a blank
# delegatable_actions as NONE (operator rule 2026-09-08: a blank permission
# list means deny). Every row written before meant "any action" by the same
# bytes, so each is rewritten to the explicit list of what it permitted — the
# one action type delegation is checked as, Ai::DelegationPolicy::DELEGATABLE_ACTIONS
# at the time of writing (spelled literally here so a later change to the
# constant cannot change what this migration did).
class MakeBlankDelegatableActionsExplicit < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE ai_delegation_policies
         SET delegatable_actions = '["execute"]'::jsonb, updated_at = NOW()
       WHERE delegatable_actions = '[]'::jsonb
    SQL
  end

  # A repaired row cannot be told apart from one written ["execute"] on purpose.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

# frozen_string_literal: true

# IMP-89c398dcbc15 — one row per policy identity. Pairs with
# 20260930130000_dedupe_ai_intervention_policies.rb, which removes the copies
# this index would otherwise refuse to build over.
#
# THE KEY, and why each column is in it:
#
#   account_id, scope, ai_agent_id, user_id, action_category, priority, conditions
#
#   * priority and conditions are IN it because rows share the other five on
#     purpose as conditional tiers (auto_approve@20 under trust_tier_minimum
#     "trusted" beside require_approval@10): a key without them would forbid the
#     trust-tier safety mechanism.
#   * is_active is OUT: an inactive copy is still a copy. In it, the seeds
#     would find no row for an operator-deactivated policy and create an active
#     one beside it, reviving what the operator turned off.
#   * policy, approval_chain_id and preferred_channels are OUT: they are the
#     payload, and two rows differing only there ARE the conflict this prevents.
#
# NULLS NOT DISTINCT (PG15+; the platform runs 16+): ai_agent_id and user_id are
# nullable, and the default unique semantics treat NULLs as all-different, so two
# agent-less rows would never collide, which is exactly the shape the account
# wide floors and the global seeds write.
#
# conditions is indexed as jsonb directly. jsonb equality is canonical (key
# order and whitespace do not matter), so no expression index is needed. The
# alternative, md5(conditions::text), avoids the ~2.7 kB btree row limit but
# hides the key behind an expression the model and seeds would have to repeat;
# conditions here are tiny (a tier, an environment list, quiet hours), and the
# model validation refuses a duplicate before the database is asked. The column
# is made NOT NULL first, because NULL and {} would otherwise be two different
# values to the index.
#
# NEVER RAISES (the 09-28 boot crash-loop): a failed dedup leaves duplicates, and
# building a unique index over them would abort. This migration counts them
# first and SKIPS with a warning; rerun it (`rails db:migrate:redo
# VERSION=20260930130100`) after they are resolved. Every DDL step is rescued.
#
# Guarded by index_exists?: server/db/schema.rb already carries the index, so a
# fresh schema:load followed by migrate must not try to add it again.
class AddUniqueFullKeyIndexToAiInterventionPolicies < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLE   = :ai_intervention_policies
  INDEX   = "idx_ai_intervention_policies_full_key"
  COLUMNS = %i[account_id scope ai_agent_id user_id action_category priority conditions].freeze

  DUPLICATE_SETS_SQL = <<~SQL
    SELECT COUNT(*) FROM (
      SELECT 1 FROM ai_intervention_policies
       GROUP BY account_id, scope, ai_agent_id, user_id, action_category, priority, conditions
      HAVING COUNT(*) > 1
    ) sets
  SQL

  def up
    return say("#{INDEX} already exists, skipping") if index_exists?(TABLE, COLUMNS, name: INDEX)

    normalise_conditions
    remaining = connection.select_value(DUPLICATE_SETS_SQL).to_i
    if remaining.positive?
      return warn_skipped("#{remaining} duplicate set(s) remain (run 20260930130000 / resolve them, then redo this migration)")
    end

    add_index TABLE, COLUMNS, unique: true, nulls_not_distinct: true, name: INDEX
    say "IMP-89c398dcbc15: created #{INDEX}"
  rescue StandardError => e
    warn_skipped("#{e.class}: #{e.message.to_s.lines.first.to_s.strip}")
  end

  def down
    remove_index TABLE, name: INDEX if index_name_exists?(TABLE, INDEX)
    change_column_null TABLE, :conditions, true
  end

  private

  # NULL and a JSON null are both "no conditions" to every reader
  # (Ai::InterventionPolicy#conditions_met? tests conditions.blank?).
  def normalise_conditions
    connection.execute("UPDATE #{TABLE} SET conditions = '{}'::jsonb WHERE conditions IS NULL OR conditions = 'null'::jsonb")
    change_column_null TABLE, :conditions, false
  end

  def warn_skipped(reason)
    message = "IMP-89c398dcbc15: unique index #{INDEX} NOT created (#{reason})"
    say message
    Rails.logger.warn("[Migration] #{message}")
  end
end

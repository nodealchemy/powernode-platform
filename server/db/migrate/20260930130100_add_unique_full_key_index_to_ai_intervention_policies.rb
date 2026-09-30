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
# building a unique index over them would abort. This migration therefore runs
# the same dedup itself, right before the index (a transient failure of
# 20260930130000 is healed here), then counts what is left and SKIPS with a
# warning if any remain. Every step is rescued.
#
# A skipped run is STAMPED, so `db:migrate` never retries it. What makes that
# visible instead of silent: System::SchemaDriftDetector, which the hub's
# rails-start.sh runs after every db:migrate (schema-drift-check.rb), reads the
# literal `add_index ... name: "..."` line below in every stamped migration and
# emits a high-severity System::FleetEvent when the index is absent. Keep that
# line a single-line literal, and never write a literal remove_index for it
# (the detector would net the two out). To retry by hand: `rails db:migrate:redo
# VERSION=20260930130100`.
#
# Guarded by index_exists?: server/db/schema.rb already carries the index, so a
# fresh schema:load followed by migrate must not try to add it again.
class AddUniqueFullKeyIndexToAiInterventionPolicies < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  TABLE   = :ai_intervention_policies
  INDEX   = "idx_ai_intervention_policies_full_key"
  COLUMNS = %i[account_id scope ai_agent_id user_id action_category priority conditions].freeze

  # The dedup of 20260930130000, standing alone (a migration must not depend on
  # another migration file): keep the greatest updated_at, then the greatest id,
  # per full key. Run after normalise_conditions, so conditions compare directly.
  HEAL_SQL = <<~SQL
    DELETE FROM ai_intervention_policies
     WHERE id IN (
       SELECT id FROM (
         SELECT id, ROW_NUMBER() OVER (
                  PARTITION BY account_id, scope, ai_agent_id, user_id, action_category, priority, conditions
                  ORDER BY updated_at DESC, id DESC
                ) AS rn
           FROM ai_intervention_policies
       ) ranked
        WHERE rn > 1
     )
    RETURNING id, action_category, policy, priority
  SQL

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
    heal_duplicates
    remaining = connection.select_value(DUPLICATE_SETS_SQL).to_i
    if remaining.positive?
      return warn_skipped("#{remaining} duplicate set(s) remain (run 20260930130000 / resolve them, then redo this migration)")
    end

    add_index :ai_intervention_policies, %i[account_id scope ai_agent_id user_id action_category priority conditions], unique: true, nulls_not_distinct: true, name: "idx_ai_intervention_policies_full_key"
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

  # Deletes only when duplicates exist, and says exactly what it removed.
  def heal_duplicates
    return if connection.select_value(DUPLICATE_SETS_SQL).to_i.zero?

    connection.select_all(HEAL_SQL).each do |row|
      line = "IMP-89c398dcbc15: removed leftover duplicate #{row['id']} #{row['action_category']} " \
             "policy=#{row['policy']} priority=#{row['priority']}"
      say line
      Rails.logger.warn("[Migration] #{line}")
    end
  end

  def warn_skipped(reason)
    message = "IMP-89c398dcbc15: unique index #{INDEX} NOT created (#{reason})"
    say message
    Rails.logger.warn("[Migration] #{message}")
  end
end

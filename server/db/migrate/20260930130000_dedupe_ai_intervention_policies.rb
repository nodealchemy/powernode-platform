# frozen_string_literal: true

# IMP-89c398dcbc15 — remove duplicate Ai::InterventionPolicy rows, keeping the
# most recently updated of each set.
#
# WHAT A DUPLICATE IS. The FULL key:
#
#   (account_id, scope, ai_agent_id, user_id, action_category, priority, conditions)
#
# NOT the five columns without priority and conditions. Rows share those five on
# purpose as CONDITIONAL TIERS: dev.prompt_refine on one agent is
# `auto_approve, priority 20, {"trust_tier_minimum":"trusted"}` beside
# `require_approval, priority 10, {}`, and that pair IS the trust-tier safety
# mechanism (ai_engineering_agents_seed.rb). Collapsing on the five columns
# would delete one half of it and change what an agent is allowed to do.
# `is_active` is deliberately NOT part of the key: an inactive copy of an active
# row is still a copy, and the seeds would otherwise keep re-creating the
# active one beside it.
#
# WHICH ROW SURVIVES. The greatest `updated_at`; on a tie the greatest id. The
# operator ruled (2026-09-27) that the most recent row wins, which is also the
# right call for the one CONFLICTING set observed on the live hub
# (release.promote: auto_approve updated 09-27 against require_approval from
# 09-05 — the operator's edit is the newer). Every removal that DISAGREES with
# its survivor on the verb is flagged CONFLICT in the output.
#
# THIS MUST NOT RAISE. A raising data migration crash-loops Rails at boot (the
# 09-28 outage), so the whole body is rescued: a failure logs and leaves every
# row where it was, and the following migration (the unique index) skips itself
# while duplicates remain instead of failing.
#
# Reported to the migration output and Rails.logger, NOT to the audit log: the
# audit sink rate-limits deletes and swallows outside test, so a 22-row removal
# would be truncated and the record could not be relied on.
#
# Table-only SQL, no model: a migration must run standing alone.
class DedupeAiInterventionPolicies < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Postgres treats NULL partition keys as equal, which is what a duplicate set
  # needs for the nullable ai_agent_id / user_id. conditions is normalised so a
  # NULL and {} are the same row (the index migration makes them one value).
  SURPLUS_SQL = <<~SQL
    SELECT id, kept_id, kept_policy, action_category, scope, ai_agent_id, agent_name, user_id,
           policy, priority, updated_at
      FROM (
        SELECT p.id, p.action_category, p.scope, p.ai_agent_id, p.user_id, p.policy, p.priority, p.updated_at,
               a.name AS agent_name,
               ROW_NUMBER()     OVER w AS rn,
               FIRST_VALUE(p.id)     OVER w AS kept_id,
               FIRST_VALUE(p.policy) OVER w AS kept_policy
          FROM ai_intervention_policies p
          LEFT JOIN ai_agents a ON a.id = p.ai_agent_id
         WINDOW w AS (
           PARTITION BY p.account_id, p.scope, p.ai_agent_id, p.user_id, p.action_category, p.priority,
                        COALESCE(NULLIF(p.conditions, 'null'::jsonb), '{}'::jsonb)
           ORDER BY p.updated_at DESC, p.id DESC
         )
      ) ranked
     WHERE rn > 1
     ORDER BY action_category, ai_agent_id NULLS FIRST, priority, updated_at DESC
  SQL

  def up
    surplus = surplus_rows
    say "IMP-89c398dcbc15: #{surplus.size} surplus intervention policy row(s) to remove"
    return if surplus.empty?

    surplus.each { |row| report(row) }
    delete_rows(surplus.map { |row| row["id"] })
    say "IMP-89c398dcbc15: removed #{surplus.size} row(s)"
  rescue StandardError => e
    # Never re-raise: see the header. The rows stay, and the index migration
    # skips while they do.
    message = "IMP-89c398dcbc15: intervention policy dedup FAILED, no rows were removed " \
              "(#{e.class}: #{e.message.to_s.lines.first.to_s.strip})"
    say message
    Rails.logger.error("[Migration] #{message}")
  end

  def down
    # The removed rows were exact copies of a survivor; there is nothing to restore.
  end

  private

  def surplus_rows
    connection.select_all(SURPLUS_SQL).to_a
  end

  def delete_rows(ids)
    transaction do
      connection.execute("DELETE FROM ai_intervention_policies WHERE id IN (#{ids.map { |id| connection.quote(id) }.join(', ')})")
    end
  end

  def report(row)
    verdict = row["policy"] == row["kept_policy"] ? "same verb" : "CONFLICT, kept #{row['kept_policy']}"
    line = "IMP-89c398dcbc15: removed #{row['id']} #{row['action_category']} " \
           "scope=#{row['scope']} agent=#{row['agent_name'] || row['ai_agent_id'] || '-'} " \
           "policy=#{row['policy']} priority=#{row['priority']} updated_at=#{row['updated_at']} " \
           "(kept #{row['kept_id']}; #{verdict})"
    say line
    Rails.logger.info("[Migration] #{line}")
  end
end

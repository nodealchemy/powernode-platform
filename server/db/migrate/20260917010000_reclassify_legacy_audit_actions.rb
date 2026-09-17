# frozen_string_literal: true

# IMP-85fb47438be6. AuditActions::LEGACY_ACTIONS (the deprecated ai_<domain>.<verb>
# alias shape — ai_agents.index, ai_conversations.create, ai_messages.update,
# ai_analytics.usage_recorded, ...) is deleted from the allowlist in the same
# change that adds this migration. AI_AGENT_TEAM_ACTIONS (ai_agent_team.*) was
# separately renamed to the dot convention (ai.agent_team.*) in the same change,
# for the same no-legacy-shape reason (operator decision 2026-09-17, following
# review). This data migration is the "existing rows" half of both renames.
#
# ── DOES NOT RENAME OR RE-CHAIN SEALED ROWS ───────────────────────────────
#
# `action` is a HASHED field: Audit::LogIntegrityService#build_hash_data covers
# id, action, resource_type, resource_id, user_id, account_id, ip_address,
# user_agent, metadata, created_at, sequence_number and previous_hash. Renaming
# a sealed row's action would:
#   (a) if left un-resealed, make verify_entry/verify_chain report that row (and
#       the chain from it forward) as tampered;
#   (b) if resealed, change that row's integrity_hash and force re-chaining
#       every later row — diverging from any exported chain (export_chain) and
#       from the integrity_hash/sequence_number anchors mirrored into
#       ai_data_source_queries metadata (Audit::QueryService).
# Operator ruling 2026-09-13 on IMP-85fb47438be6 is explicit: do NOT rename or
# re-chain sealed rows. NO row is ever UPDATEd by this migration — only INSERT.
#
# ── APPEND, DON'T EDIT — AND THE PAYLOAD MUST BE IN A HASHED COLUMN ────────
#
# For every row whose action is one of the retired legacy names, this appends
# ONE new row via the normal AuditLog.create! path (so it goes through
# redact_secret_values / apply_integrity_hash exactly like any other write and
# EXTENDS the chain rather than editing it):
#   action:      "audit.action_reclassified"
#   resource:    AuditLog/<legacy row id>
#   metadata:    { "reclassified_action_from" => <legacy>, "reclassified_action_to" => <canonical> }
#   old_values:  { "action" => <legacy name> }   (non-authoritative duplicate)
#   new_values:  { "action" => <canonical name> } (non-authoritative duplicate)
#
# THE PAYLOAD LIVES IN metadata, not old_values/new_values, on purpose (review
# finding F1, 2026-09-17): being a NEW row does not by itself make a payload
# tamper-evident — only landing it in a column build_hash_data actually covers
# does. old_values/new_values are NOT in that covered list (metadata IS), so
# anyone with UPDATE on audit_logs could rewrite old_values/new_values on a
# correction row and verify_entry/verify_chain would stay green — exactly the
# precedent 20260905050000_scrub_historical_audit_log_secrets.rb relies on to
# justify rewriting those same two columns on OTHER sealed rows. Putting the
# {from, to} pair in metadata instead means tampering with it breaks the hash,
# same as tampering with the row's action would. old_values/new_values still
# carry the identical pair as a convenience duplicate for tooling that reads
# those columns by habit; they are not where the guarantee lives.
#
# FLAT, NOT NESTED, deliberately: Audit::LogIntegrityService#normalize_details
# sorts metadata's TOP-LEVEL keys before hashing (so jsonb's undocumented top-
# level key ordering — Postgres explicitly does not preserve object key order
# in jsonb — can't desync the hash computed at write time from the hash
# recomputed against a freshly-reloaded row) but does NOT recursively sort
# nested hash values. A first attempt at this migration nested the pair as
# metadata: {"reclassified_action" => {"from" => ..., "to" => ...}} and its own
# spec caught the fallout directly: verify_entry read the freshly-reloaded
# correction row as tampered (Hash mismatch) even with NOTHING touched,
# because Postgres round-tripped the nested hash's key order between write and
# read while the in-memory object used at write time never went through that
# round trip. Two flat top-level keys sidestep the nested case entirely.
# Ai::SensitiveParams.filter (run by AuditLog#redact_secret_values on every
# metadata write) does not touch this payload: neither
# "reclassified_action_from" nor "reclassified_action_to" match its key
# patterns (token/secret/password/.../credential).
#
# The legacy row itself is left byte-for-byte untouched. Readers keep filtering
# on the raw, stored (legacy) action name — `AuditLog.where(action: ...)` still
# finds these rows under the name they were written with.
#
# ── COUNTS AT RUN TIME, HARDCODED MAPPING ─────────────────────────────────
#
# The live count of legacy-named rows was unmeasured at authoring time (the
# task's re-verification found no code that WRITES one of these names in core,
# worker, or the two populated public extensions at the time of writing —
# `extensions/marketing` was empty and private extensions were absent in the
# checkout this was verified in, so that is what was actually checked, not a
# claim about every possible deployment or history). Expected count is
# therefore zero, but this runs the correction unconditionally so it is
# correct whichever the actual count turns out to be. Zero legacy rows: #up is
# a no-op. The 28-pair mapping below (20 AuditActions::LEGACY_ACTIONS pairs +
# 8 AI_AGENT_TEAM_ACTIONS rename pairs) is hardcoded rather than read from any
# application constant, deliberately: both source constants are deleted/renamed
# by this same change, and a migration — a historical artifact — must not
# depend on application constants that keep changing.
#
# ── NOT WRAPPED IN THE MIGRATION'S OWN TRANSACTION ─────────────────────────
#
# disable_ddl_transaction! (review finding F5, 2026-09-17): AuditLog#apply_integrity_hash
# takes pg_advisory_xact_lock(SEQUENCE_LOCK_KEY) and holds it for the
# lifetime of the CURRENT transaction. Left wrapped in Rails' default
# single-transaction-per-migration, the first #create! would hold that lock
# — blocking every other audit write in the whole system — until the ENTIRE
# migration commits, i.e. until every legacy row has been processed. The
# sibling scrub migration (20260905050000) reasoned explicitly about not
# holding long locks on this same table for exactly this kind of one-off
# cleanup; this migration adopts the same posture. Each #create! now commits
# on its own, so the lock is held only per-row.
# This is what makes idempotency load-bearing rather than a nicety: a crash or
# a manual re-run partway through must not double-correct rows already
# committed. already_corrected_ids (below) is what makes a partial run safe to
# resume — it is checked, not assumed.
class ReclassifyLegacyAuditActions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LEGACY_TO_CANONICAL = {
    # AI Agents legacy -> standardized
    "ai_agents.index" => "ai.agents.read",
    "ai_agents.create" => "ai.agents.create",
    "ai_agents.update" => "ai.agents.update",
    "ai_agents.destroy" => "ai.agents.delete",
    "ai_agents.execute" => "ai.agents.execute",
    "ai_agents.clone" => "ai.agents.clone",
    "ai_agents.pause" => "ai.agents.pause",
    "ai_agents.resume" => "ai.agents.resume",
    "ai_agents.archive" => "ai.agents.archive",
    "ai_agents.stats" => "ai.agents.stats",
    "ai_agents.analytics" => "ai.agents.analytics",

    # AI Conversations legacy -> standardized
    "ai_conversations.create" => "ai.conversations.create",
    "ai_conversations.update" => "ai.conversations.update",
    "ai_conversations.destroy" => "ai.conversations.delete",

    # AI Messages legacy -> standardized
    "ai_messages.create" => "ai.messages.create",
    "ai_messages.update" => "ai.messages.update",
    "ai_messages.destroy" => "ai.messages.delete",
    "ai_messages.edit_content" => "ai.messages.edit_content",

    # AI Analytics legacy -> standardized
    "ai_analytics.usage_recorded" => "ai.analytics.usage_recorded",
    "ai_analytics.update" => "ai.analytics.update",

    # AI Agent Team legacy (underscore-namespace) -> dot convention.
    # Not an alias of the ai_agents.*/ai_conversations.*/ai_messages.*/
    # ai_analytics.* family above — a separate rename decided in the same
    # review round (operator decision 2026-09-17), same treatment.
    "ai_agent_team.created" => "ai.agent_team.created",
    "ai_agent_team.updated" => "ai.agent_team.updated",
    "ai_agent_team.deleted" => "ai.agent_team.deleted",
    "ai_agent_team.member_added" => "ai.agent_team.member_added",
    "ai_agent_team.member_removed" => "ai.agent_team.member_removed",
    "ai_agent_team.execution_started" => "ai.agent_team.execution_started",
    "ai_agent_team.execution_completed" => "ai.agent_team.execution_completed",
    "ai_agent_team.execution_failed" => "ai.agent_team.execution_failed"
  }.freeze

  CORRECTION_ACTION = "audit.action_reclassified"
  CORRECTION_RESOURCE_TYPE = "AuditLog"

  # Returns the number of correction rows it created, so a caller (and the
  # spec) can assert a second run does nothing rather than merely re-doing
  # identical work.
  def up
    legacy_rows = AuditLog.where(action: LEGACY_TO_CANONICAL.keys)
    total_legacy = legacy_rows.count

    if total_legacy.zero?
      say "no legacy-named audit_logs rows found; no-op"
      return 0
    end

    # `resource_id` is varchar(36); `id` is uuid. Materialize the legacy ids as
    # a plain Ruby array (pluck) rather than a subquery — comparing the two
    # column types directly in SQL (`resource_id = <uuid>`) raises
    # PG::UndefinedFunction: operator does not exist: character varying = uuid.
    already_corrected_ids = AuditLog
      .where(action: CORRECTION_ACTION, resource_type: CORRECTION_RESOURCE_TYPE)
      .where(resource_id: legacy_rows.pluck(:id))
      .pluck(:resource_id)

    pending = legacy_rows.where.not(id: already_corrected_ids)
    pending_count = pending.count

    say "found #{total_legacy} legacy-named audit_logs row(s), #{pending_count} pending correction"
    return 0 if pending_count.zero?

    corrected = 0
    pending.find_each do |row|
      canonical = LEGACY_TO_CANONICAL.fetch(row.action)

      AuditLog.create!(
        account_id: row.account_id,
        user_id: row.user_id,
        action: CORRECTION_ACTION,
        resource_type: CORRECTION_RESOURCE_TYPE,
        resource_id: row.id,
        source: "system",
        metadata: { "reclassified_action_from" => row.action, "reclassified_action_to" => canonical },
        old_values: { "action" => row.action },
        new_values: { "action" => canonical }
      )
      corrected += 1
    end

    say "appended #{corrected} correction row(s)"
    corrected
  end

  # Deliberately irreversible. The correction rows are themselves sealed chain
  # links by the time #up returns (each went through apply_integrity_hash);
  # deleting them would punch holes in sequence_number, and there is nothing
  # else to roll back — no row was renamed or edited.
  def down
    raise ActiveRecord::IrreversibleMigration,
          "Correction rows extend the audit chain; removing them would break sequence continuity. " \
          "No original row was renamed or edited, so there is nothing to revert."
  end
end

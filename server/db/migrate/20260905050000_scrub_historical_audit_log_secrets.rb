# frozen_string_literal: true

# IMP-fd0340138880. Retroactive scrub of secret payloads captured in audit_logs
# BEFORE the write-path filter existed.
#
# IMP-d81452620204 stopped the WRITE — Auditable#redact_audit_values now honours
# each model's filter_attributes, and Devops::KubernetesCluster declares its
# three credential columns on that list. It added no backfill, and its operator
# direction deferred the purge here deliberately. Rows written before it are
# untouched: `command grep -rn "old_values\|new_values" db/migrate` returns only
# the two COLUMN DEFINITIONS in the 2025 baseline, so nothing has ever rewritten
# these columns.
#
# HOW EXPOSED, corrected after review — both halves of an earlier draft of this
# paragraph were wrong, in the direction that UNDERSTATED it:
#   - Not "only the manual admin endpoint": there are three purge paths, and two
#     default to 90 days, not a year (audit_logs_controller.rb#cleanup;
#     Data Management cleanup_service.rb#cleanup_audit_logs; the worker's
#     scheduled_task_executor_job). Old rows may or may not have aged out —
#     which is a data-state question, not a code one.
#   - Not "admin.audit.read": the read endpoints gate on `audit.read`
#     (audit_logs_controller.rb:5), which config/permissions.rb grants to the
#     ordinary MEMBER role (:744). GET /api/v1/audit_logs/:id returns both
#     columns verbatim. The audience is every member of an account, not its
#     admins.
#
# ── SCRUB IN PLACE, NOT DELETE ────────────────────────────────────────────
#
# The row's value is the audit fact — who did what, when, from where — and the
# payload is one field of it. Deleting rows destroys evidence to remove a
# secret, which is the wrong trade for an AUDIT log, and would also punch holes
# in the sequence_number chain. Each targeted key keeps its KEY and loses its
# VALUE, mirroring exactly what the forward path now writes
# (Auditable::REDACTED_PLACEHOLDER), so history and present policy agree and an
# auditor can still see THAT a credential attribute was set or changed.
#
# Overwritten in place. No backup table, no shadow column: the point is that the
# plaintext stops existing.
#
# ── WHY THIS DOES NOT BREAK THE INTEGRITY CHAIN ───────────────────────────
#
# audit_logs is a hash chain (integrity_hash / previous_hash / sequence_number).
# Audit::LogIntegrityService#build_hash_data hashes exactly: id, action,
# resource_type, resource_id, user_id, account_id, ip_address, user_agent,
# metadata, created_at, sequence_number, previous_hash. old_values and
# new_values are NOT in it — verified by reading that method, not assumed — so
# rewriting them leaves every hash valid and the chain verifiable.
#
# That is also the boundary: `metadata` IS hashed. If a secret is ever found in
# metadata, scrubbing it there would invalidate the chain from that row forward
# and needs its own decision. This migration does not touch metadata.
#
# ── SCOPE ─────────────────────────────────────────────────────────────────
#
# Keyed by resource_type AND key name, never by key name alone. `name` is on
# User's masked set, and an unscoped "scrub every key called name" would rewrite
# a large share of the whole table — the exact one-line-WHERE accident this was
# warned about.
#
# WHAT THIS DOES NOT REACH, stated so nobody reads it as "the plaintext stops
# existing" outright:
#   - TOP-LEVEL KEYS ONLY. jsonb_set(col, ARRAY[key], ...) rewrites one top-level
#     key; a secret nested inside a sub-object is untouched.
#   - TWO resource_types only. Of the models including Auditable, exactly ONE
#     (Devops::KubernetesCluster) declares filter_attributes; for the rest the
#     filter is an identity function, so their jsonb columns are audited
#     verbatim. That is a real CHANNEL. Whether any row outside these two types
#     currently holds a credential is a data-state question this migration
#     cannot answer and did not measure — it is not a claim in either direction.
#   - User PII reachable under OTHER types: accounts_controller.rb writes
#     new_values["administrator_email"] under resource_type "Account".
#   - UNSCRUBBABLE BY CONSTRUCTION: Audit::LoggingService#create_dummy_user_resource
#     puts a raw email address in resource_id for a failed login against an
#     unknown address. resource_id IS in build_hash_data, so rewriting it would
#     break the chain. Left alone deliberately; needs its own decision.
#   - users.reset_token_digest is neither redacted forward nor scrubbed here.
#     Deliberate: it is a digest, and the forward filter does not mask it, so
#     adding it here would put history ahead of present policy. Flagged, not
#     silently included.
#
# The key lists are hardcoded rather than read from the models. A migration is a
# historical artifact and must not depend on classes that keep changing; these
# are the sets as of 2026-09-05, derived by running the real filter over each
# model's columns.
class ScrubHistoricalAuditLogSecrets < ActiveRecord::Migration[8.1]
  # Matches Auditable::REDACTED_PLACEHOLDER. Duplicated deliberately — see above.
  PLACEHOLDER = "[FILTERED]"

  # Devops::KubernetesCluster. NOT `encrypts` attributes despite the names: v1
  # stores the cluster-admin kubeconfig and both k3s node-join tokens as
  # plaintext under an encrypted_ name (the model says so at its
  # filter_attributes declaration), which is why they were disclosed at all.
  CLUSTER_KEYS = %w[
    encrypted_kubeconfig
    encrypted_server_token
    encrypted_agent_token
  ].freeze

  # User. The genuinely secret / PII members of what the forward filter masks.
  # DELIBERATELY EXCLUDED, though the forward filter does mask them by substring:
  # email_verified, email_verified_at, email_verification_sent_at,
  # email_verification_token_expires_at, two_factor_backup_codes_generated_at.
  # Those are booleans and timestamps — they disclose nothing, and scrubbing them
  # would destroy real audit signal (when verification happened) to no benefit.
  USER_KEYS = %w[
    email
    name
    last_login_ip
    two_factor_secret
    backup_codes
    email_verification_token
    password_digest
    encrypted_password
  ].freeze

  TARGETS = {
    "Devops::KubernetesCluster" => CLUSTER_KEYS,
    "User" => USER_KEYS
  }.freeze

  BATCH_SIZE = 1_000

  # IDEMPOTENT AND RE-RUNNABLE. Each statement skips rows already holding the
  # placeholder, so a second run updates zero rows.
  #
  # Batched by ROW COUNT, not by primary-key range — there is no ORDER BY, so do
  # not read this as a key-ordered walk. Each statement touches at most
  # BATCH_SIZE rows and commits, so none holds a long lock on a live audit
  # table. The cost of that choice, stated rather than hidden: with no index on
  # old_values/new_values each batch re-scans the already-scrubbed prefix, so
  # this is quadratic in the number of matching rows. That is acceptable for a
  # one-off scrub of a bounded population and is why no index is added — adding
  # one would drag in the failed-CREATE-INDEX-CONCURRENTLY-leaves-an-INVALID-
  # index hazard for a migration that runs once.
  # Returns the number of rows rewritten, so a caller (and the spec) can assert
  # that a second run does NOTHING rather than merely rewriting identical bytes.
  # A re-run that overwrote every row with the same value would leave the table
  # byte-identical — and updated_at is not touched — so content comparison alone
  # cannot tell idempotent from wasteful.
  def up
    TARGETS.sum do |resource_type, keys|
      keys.sum do |key|
        %w[old_values new_values].sum do |column|
          scrub(resource_type: resource_type, column: column, key: key)
        end
      end
    end
  end

  # Deliberately irreversible. The plaintext is destroyed on purpose; there is
  # nothing to restore it from, which is the point.
  def down
    raise ActiveRecord::IrreversibleMigration,
          "Secret payloads were overwritten in place and are unrecoverable by design."
  end

  private

  def scrub(resource_type:, column:, key:)
    total = 0

    # BREAK ON ZERO, NOT ON A SHORT BATCH. FOR UPDATE SKIP LOCKED omits rows a
    # concurrent transaction holds, and audit_logs IS concurrently written —
    # anonymise runs `update_all` account-wide (internal/users_controller.rb,
    # internal/accounts_controller.rb) and two cleanup paths run `delete_all`.
    # So a batch can come back short with rows still to do; `break if updated <
    # BATCH_SIZE` would exit leaving those rows in plaintext while printing a
    # total that looked complete. Zero updated is the only safe "nothing left".
    #
    # Termination is guaranteed by the predicate, not by the batch size: every
    # row this updates stops matching `->> key IS DISTINCT FROM placeholder`, so
    # the candidate set strictly shrinks.
    loop do
      updated = execute_scrub_batch(resource_type: resource_type, column: column, key: key)
      total += updated
      break if updated.zero?
    end

    # Counts only. NEVER the contents — this log is read by operators and agents,
    # and a migration that prints what it redacted defeats itself.
    say "scrubbed #{total} #{resource_type} row(s): #{column}.#{key}" if total.positive?

    total
  end

  def execute_scrub_batch(resource_type:, column:, key:)
    result = connection.exec_update(<<~SQL.squish, "scrub_audit_secret", [ resource_type, key, PLACEHOLDER ])
      UPDATE audit_logs SET #{column} = jsonb_set(#{column}, ARRAY[$2], to_jsonb($3::text))
      WHERE id IN (
        SELECT id FROM audit_logs
        WHERE resource_type = $1
          AND #{column} ? $2
          AND #{column} ->> $2 IS DISTINCT FROM $3
        LIMIT #{BATCH_SIZE}
        FOR UPDATE SKIP LOCKED
      )
    SQL

    result.to_i
  end
end

# frozen_string_literal: true

# IMP-8b25fb48368e: Database::Backup#created_by was `belongs_to ..., class_name:
# "User"` (required by default) and the DB column itself was `null: false` — a
# worker-initiated backup (Api::V1::Internal::MaintenanceController#create_backup,
# the only caller) has no user, so every save failed both the Rails presence
# validation AND, once that validation was relaxed to `optional: true`, the
# Postgres NOT NULL constraint (confirmed empirically: PG::NotNullViolation on
# created_by_id). This migration is the DB-level half of that fix — the FK and
# index are unchanged.
class AllowNullCreatedByOnDatabaseBackups < ActiveRecord::Migration[8.1]
  def up
    change_column_null :database_backups, :created_by_id, true
  end

  # Mirrors 20260917120000_allow_system_provider_for_webhook_events' down:
  # refuse loudly with the exact count rather than let `change_column_null`
  # fail obscurely (or worse, silently coerce rows) once real created_by-nil
  # rows exist. Once the worker's create_backup path has run in an
  # environment, that is expected, not exceptional — rolling back would
  # require an operator to decide what happens to those rows (backfill a
  # synthetic user, which IMP-8b25fb48368e explicitly rejected doing even
  # forward, or delete them), not something a migration should do as a side
  # effect of `db:rollback`.
  def down
    orphaned = select_value(
      "SELECT COUNT(*) FROM database_backups WHERE created_by_id IS NULL"
    ).to_i

    if orphaned.positive?
      raise ActiveRecord::IrreversibleMigration,
            "Rolling back would make #{orphaned} database_backups row(s) with created_by_id IS NULL " \
            "violate the restored NOT NULL constraint. This rollback does not attempt to backfill or " \
            "delete those rows — an operator must decide that explicitly."
    end

    change_column_null :database_backups, :created_by_id, false
  end
end

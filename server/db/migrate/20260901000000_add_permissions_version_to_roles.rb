# frozen_string_literal: true

# IMP-95e4904258c8 — give a role's GRANT SET a version that a cache key can observe.
#
# User#permission_names is Rails.cache-backed, and its key was built from the
# user's own updated_at plus the ids of the roles it holds. Neither component can
# see a change to what those roles GRANT, so after a narrowing the cached (WIDER)
# permission set stayed addressable for the whole 5-minute TTL — and
# Role#assignable_by? resolves the privilege-escalation subset check through it,
# so conferring a whole role FAILED OPEN, durably (the delegation row outlives
# the cache window).
#
# WHY A DB TRIGGER AND NOT AN ActiveRecord CALLBACK. The narrowings that matter
# ship as raw-SQL remap migrations (`DELETE FROM role_permissions ...` issued
# through #execute). Those instantiate no model and fire no callback, so a
# callback-based buster is the same shape as the bug it is meant to fix. A
# trigger is the only form that survives raw SQL.
#
# ENABLE ALWAYS, AND THE ONE BYPASS IT CANNOT CLOSE. The triggers are set
# ENABLE ALWAYS so they still fire in a session with
# session_replication_role = 'replica' — the mode a logical-replication apply
# worker runs in. That does NOT make them unbypassable, and the limit is worth
# stating rather than discovering:
# ActiveRecord::ConnectionAdapters::PostgreSQL::ReferentialIntegrity
# #disable_referential_integrity (activerecord-8.1.3, referential_integrity.rb:7-38)
# brackets its block with `ALTER TABLE <t> DISABLE TRIGGER ALL` /
# `ENABLE TRIGGER ALL`. The first disables these triggers outright for the
# duration; the second re-enables them as ORIGIN, silently and PERMANENTLY
# discarding the ALWAYS setting. Nothing inside Postgres can prevent that. No
# application or extension code calls it (verified by grep over server/ and
# extensions/); its live callers are DatabaseCleaner and Rails' fixture loader,
# i.e. the test harness — which is why the test database's copies of these
# triggers read tgenabled='O' after any suite run. Note the reset is TABLE-WIDE
# across every table it is handed, so any other ENABLE ALWAYS trigger added
# later is downgraded by the same pass. A manual
# `ALTER TABLE role_permissions DISABLE TRIGGER ...` from psql is likewise not
# closed and is not currently detected; the cheap remedy is to assert
# pg_trigger.tgenabled='A' from the fleet's existing schema-drift check.
#
# COSTS THIS ADDS, STATED SO THEY ARE NOT DISCOVERED. A multi-row statement
# bumps the SAME roles row once per row (N dead tuples, N row-lock
# acquisitions — Role#sync_permissions! on a 40-grant role is ~40 bumps), and a
# grant edit now takes a row lock on `roles`, so two transactions editing roles
# A and B in opposite order can deadlock where they previously could not.
# Both are admin-initiated, rare, and Postgres errors rather than hangs; the
# row form is kept over a statement trigger with transition tables for
# simplicity.
class AddPermissionsVersionToRoles < ActiveRecord::Migration[8.1]
  # NOTE: this SQL is duplicated, deliberately and with a cross-reference, in
  # config/initializers/role_permissions_version_schema_dump.rb — Rails' :ruby
  # schema format does not dump functions or triggers, so `db:schema:load` on a
  # fresh database needs its own copy (the same arrangement as the uuidv7()
  # shim). A migration must keep working forever, so it does not reach into an
  # initializer for a constant.
  def up
    # PG11+: a non-volatile DEFAULT is metadata-only, so this does not rewrite a
    # populated roles table. Existing rows start at 0; no version is bumped for
    # already-present role_permissions rows, which is correct — the key FORMAT
    # also changes in this release, so every pre-existing cache entry is
    # unreachable from the moment the new code deploys.
    add_column :roles, :permissions_version, :bigint, null: false, default: 0

    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION bump_role_permissions_version() RETURNS trigger AS $$
      BEGIN
        IF (TG_OP = 'DELETE') THEN
          UPDATE roles SET permissions_version = permissions_version + 1
            WHERE id = OLD.role_id;
          RETURN OLD;
        ELSIF (TG_OP = 'UPDATE') THEN
          -- IN () de-duplicates when role_id did not change, so a plain UPDATE
          -- bumps exactly once; a re-parenting UPDATE bumps BOTH roles.
          UPDATE roles SET permissions_version = permissions_version + 1
            WHERE id IN (NEW.role_id, OLD.role_id);
          RETURN NEW;
        ELSE
          UPDATE roles SET permissions_version = permissions_version + 1
            WHERE id = NEW.role_id;
          RETURN NEW;
        END IF;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    # TRUNCATE fires no row trigger at all, so it needs its own statement-level
    # one. Bumping every role is the conservative answer: after a TRUNCATE no
    # role grants anything, and every cached set is wrong.
    execute(<<~SQL)
      CREATE OR REPLACE FUNCTION bump_all_role_permissions_versions() RETURNS trigger AS $$
      BEGIN
        UPDATE roles SET permissions_version = permissions_version + 1;
        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    execute("DROP TRIGGER IF EXISTS role_permissions_version_bump ON role_permissions;")
    execute(<<~SQL)
      CREATE TRIGGER role_permissions_version_bump
      AFTER INSERT OR UPDATE OR DELETE ON role_permissions
      FOR EACH ROW EXECUTE FUNCTION bump_role_permissions_version();
    SQL
    execute("ALTER TABLE role_permissions ENABLE ALWAYS TRIGGER role_permissions_version_bump;")

    execute("DROP TRIGGER IF EXISTS role_permissions_version_bump_truncate ON role_permissions;")
    execute(<<~SQL)
      CREATE TRIGGER role_permissions_version_bump_truncate
      AFTER TRUNCATE ON role_permissions
      FOR EACH STATEMENT EXECUTE FUNCTION bump_all_role_permissions_versions();
    SQL
    execute("ALTER TABLE role_permissions ENABLE ALWAYS TRIGGER role_permissions_version_bump_truncate;")
  end

  def down
    execute("DROP TRIGGER IF EXISTS role_permissions_version_bump_truncate ON role_permissions;")
    execute("DROP TRIGGER IF EXISTS role_permissions_version_bump ON role_permissions;")
    execute("DROP FUNCTION IF EXISTS bump_all_role_permissions_versions();")
    execute("DROP FUNCTION IF EXISTS bump_role_permissions_version();")
    remove_column :roles, :permissions_version
  end
end

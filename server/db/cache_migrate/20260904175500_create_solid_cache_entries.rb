# frozen_string_literal: true

# IMP-4c5c53574683 — `rails db:seed` on ops-hub died with
#   PG::UndefinedTable: relation "solid_cache_entries" does not exist
# and information_schema on powernode_production confirmed the table absent.
#
# db/cache_schema.rb has declared this table all along, but nothing on the deploy
# path ever applies it. ActiveRecord loads a config's schema DUMP from exactly one
# place — DatabaseTasks#initialize_database, which db:migrate calls per config —
# and only when that connection's schema_migrations table does not yet exist:
#
#     database_already_initialized = migration_connection_pool.schema_migration.table_exists?
#     unless database_already_initialized
#       load_schema(db_config) if schema_dump_path && File.exist?(schema_dump_path)
#     end
#
# All four production configs (primary/cache/queue/cable) resolve to the SAME
# physical database — DATABASE_NAME_CACHE and friends default to DATABASE_NAME —
# and configs_for yields primary first. So primary always creates the shared
# schema_migrations table before the cache config is considered, cache is always
# "already initialized", and db/cache_schema.rb is unreachable. That holds on a
# FRESH install exactly as it did on this live host; it was never a VM-600 quirk.
#
# The cache config's `migrations_paths: db/cache_migrate` is the one delivery
# mechanism that does run (migrate_all's non-primary branch), and this directory
# did not exist. Shipping the schema as a migration therefore lands it on a fresh
# install and converges an established host on its next boot, using the
# `db:migrate`-only sequence the hub already runs — no schema:load-family task,
# which the start wrapper forbids because it stamps the extension migrations as
# applied without running their DDL.
#
# Guarded rather than assertive: a host that received a manual load out of band
# already has the table, and the start wrapper runs db:migrate under `set -e`
# with no `|| true`, so a raising migration would crash-loop a sole control
# plane's Rails rather than just failing this one step.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def up
    return if connection.table_exists?(:solid_cache_entries)

    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false
      t.index [:byte_size], name: "index_solid_cache_entries_on_byte_size"
      t.index [:key_hash, :byte_size], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      # UNIQUE is load-bearing, not a nicety: solid_cache writes via an upsert
      # conflict-targeted on key_hash, which requires a unique index there.
      t.index [:key_hash], name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end

  def down
    drop_table :solid_cache_entries, if_exists: true
  end
end

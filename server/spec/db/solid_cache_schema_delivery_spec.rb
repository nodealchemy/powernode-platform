# frozen_string_literal: true

require "spec_helper"
require "erb"
require "yaml"
require "active_record"
require "active_record/database_configurations"

# IMP-4c5c53574683 — `rails db:seed` on ops-hub died with
#   PG::UndefinedTable: relation "solid_cache_entries" does not exist
# and information_schema on powernode_production confirmed the table absent.
#
# ROOT CAUSE (ActiveRecord 8.1.3, tasks/database_tasks.rb):
#   `db:migrate` -> DatabaseTasks.migrate_all runs
#   `db_configs.each { |db_config| initialize_database(db_config) }` first, and
#   initialize_database (line 651) loads a config's schema DUMP only when that
#   connection's schema_migrations table does NOT already exist:
#
#       database_already_initialized = migration_connection_pool.schema_migration.table_exists?
#       unless database_already_initialized
#         load_schema(db_config) if schema_dump_path && File.exist?(schema_dump_path)
#       end
#
#   Every production config in config/database.yml — primary, cache, queue,
#   cable — resolves to the SAME physical database (DATABASE_NAME_CACHE etc.
#   default to DATABASE_NAME). configs_for returns primary FIRST, so by the time
#   the loop reaches `cache` the shared schema_migrations table already exists,
#   `database_already_initialized` is true, and db/cache_schema.rb is skipped.
#
#   That is structural, not a one-off on VM 600: on a FRESH install the primary
#   config initializes the database before the cache config is ever considered,
#   so db/cache_schema.rb can never be reached on this deploy path. And
#   rails-start.sh deliberately runs `db:migrate` ONLY (never db:schema:load /
#   db:setup / db:prepare — see its "INVARIANT (imp 019f77c5)" block, which
#   guards against stamped-without-DDL drift of the extension migrations), so no
#   other task ever applies the dump either.
#
#   The cache config declares `migrations_paths: db/cache_migrate`, which
#   migrate_all's second branch DOES honour for every non-primary config. That
#   directory did not exist, so the cache connection had zero migrations and the
#   table was never created anywhere.
#
# FIX: deliver the solid_cache schema as a real migration under
# db/cache_migrate, so the existing `db:migrate` — which rails-start.sh runs on
# every boot, in both the first-boot and the already-initialized branch — creates
# it on a fresh install AND converges the live host with no manual step.
#
# These specs pin the mechanism, not just the file: if the cache database is ever
# split off from primary, the FIRST example goes red and db/cache_schema.rb
# becomes live again — which is why the schema dump's version must stay in sync
# with the migrations (last example), or a split-off deployment would load the
# dump and then try to create the table a second time.
RSpec.describe "solid_cache schema delivery (IMP-4c5c53574683)" do
  server_root = File.expand_path("../..", __dir__) # server/spec/db -> server/

  cache_schema_path = File.join(server_root, "db/cache_schema.rb")
  cache_migrate_dir = File.join(server_root, "db/cache_migrate")

  # ONE extractor, applied to BOTH artifacts, so drift in either direction fails.
  # Handles the schema-dump style (`t.binary "key"`) and the migration style
  # (`t.binary :key`) identically.
  def declared_schema(source)
    columns = {}
    indexes = {}

    source.each_line do |line|
      if (m = line.match(/^\s*t\.index\s+\[([^\]]*)\]\s*(.*)$/))
        cols = m[1].scan(/["':]?([a-z_][a-z0-9_]*)/).flatten
        rest = m[2]
        name = rest[/name:\s*["']([^"']+)["']/, 1]
        next unless name

        indexes[name] = { columns: cols.sort, unique: rest.include?("unique: true") }
      elsif (m = line.match(/^\s*t\.([a-z_]+)\s+["':]([a-z_][a-z0-9_]*)["']?\s*(.*)$/))
        type, name, rest = m[1], m[2], m[3]
        next if type == "index"

        columns[name] = {
          type: type,
          limit: rest[/limit:\s*(\d+)/, 1]&.to_i,
          null_false: rest.include?("null: false")
        }
      end
    end

    { columns: columns, indexes: indexes }
  end

  let(:production_configs) do
    raw = ERB.new(File.read(File.join(server_root, "config/database.yml"))).result
    ActiveRecord::DatabaseConfigurations.new(YAML.unsafe_load(raw))
                                        .configs_for(env_name: "production")
  end

  it "pins the root cause: the cache config shares the primary database, so its schema dump is unreachable on db:migrate" do
    primary = production_configs.find(&:primary?)
    cache   = production_configs.find { |c| c.name == "cache" }

    expect(primary).not_to be_nil
    expect(cache).not_to be_nil

    # Same physical database => the shared schema_migrations table already exists
    # by the time initialize_database reaches the cache config, so load_schema is
    # skipped and db/cache_schema.rb is dead on this path.
    expect(cache.database).to eq(primary.database),
      "cache no longer shares the primary database — initialize_database can now load " \
      "db/cache_schema.rb, so re-check that it agrees with db/cache_migrate"

    # ...which leaves migrations_paths as the ONLY delivery mechanism.
    expect(cache.migrations_paths).to eq("db/cache_migrate")
  end

  it "ships a cache migration that creates solid_cache_entries" do
    expect(Dir.exist?(cache_migrate_dir)).to be(true),
      "db/cache_migrate does not exist, so the cache connection has zero migrations " \
      "and solid_cache_entries is never created on any install"

    migrations = Dir[File.join(cache_migrate_dir, "*.rb")].sort
    expect(migrations).not_to be_empty

    combined = migrations.map { |f| File.read(f) }.join("\n")
    expect(combined).to match(/create_table\s+["':]solid_cache_entries/)
  end

  it "creates exactly the columns and indexes db/cache_schema.rb declares" do
    expect(Dir.exist?(cache_migrate_dir)).to be(true)

    dump      = declared_schema(File.read(cache_schema_path))
    migration = declared_schema(Dir[File.join(cache_migrate_dir, "*.rb")].sort.map { |f| File.read(f) }.join("\n"))

    expect(dump[:columns]).not_to be_empty, "cache_schema.rb parsed as empty — extractor is broken"
    expect(migration[:columns]).to eq(dump[:columns])
    expect(migration[:indexes]).to eq(dump[:indexes])

    # solid_cache's write path upserts on key_hash; a non-unique index there
    # silently permits duplicate cache entries.
    expect(migration[:indexes].fetch("index_solid_cache_entries_on_key_hash")[:unique]).to be(true)
  end

  it "keeps db/cache_schema.rb's version at the latest cache migration" do
    expect(Dir.exist?(cache_migrate_dir)).to be(true)

    latest = Dir[File.join(cache_migrate_dir, "*.rb")]
             .map { |f| File.basename(f)[/\A(\d+)_/, 1] }
             .compact.map(&:to_i).max
    expect(latest).not_to be_nil

    dumped = File.read(cache_schema_path)[/ActiveRecord::Schema\[[\d.]+\]\.define\(version:\s*([0-9_]+)\s*\)/, 1]
    expect(dumped).not_to be_nil
    expect(dumped.delete("_").to_i).to eq(latest),
      "db/cache_schema.rb declares version #{dumped} but the latest cache migration is #{latest}; " \
      "a deployment that splits the cache database would load the dump and then re-run the migration"
  end
end

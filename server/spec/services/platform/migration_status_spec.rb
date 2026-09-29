# frozen_string_literal: true

require "rails_helper"

# IMP-d421e10d4677 — migration state as a read, so an operator does not have to
# open psql to compare schema_migrations with the files on disk.
#
# Everything here runs against a TEMP directory tree and a stubbed applied set:
# no migration file is ever written into the repo and schema_migrations is never
# touched. The .current spec at the bottom is the one place the real
# connection is read, and it only asserts shape.
RSpec.describe Platform::MigrationStatus do
  around do |example|
    Dir.mktmpdir("migration-status-spec") do |dir|
      @root = Pathname.new(dir)
      example.run
    end
  end

  let(:root) { @root }

  def write_migrations(relative_dir, *versions)
    dir = root.join(relative_dir)
    dir.mkpath
    versions.each { |version| dir.join("#{version}_change_#{version}.rb").write("# stub\n") }
    dir.to_s
  end

  def write_schema(version)
    path = root.join("db", "schema.rb")
    path.dirname.mkpath
    path.write(<<~RUBY)
      ActiveRecord::Schema[8.1].define(version: #{version.to_s.reverse.scan(/\d{1,4}/).join("_").reverse}) do
        create_table "widgets"
      end
    RUBY
    path.to_s
  end

  def status(paths:, applied:, schema_path: nil, limit: described_class::LIST_LIMIT, engine_roots: {})
    described_class.new(migrations_paths: paths, applied_versions: applied, schema_path: schema_path,
                        root: root, limit: limit, engine_roots: engine_roots).report
  end

  def write_schema_text(text)
    path = root.join("db", "schema.rb")
    path.dirname.mkpath
    path.write(text)
    path.to_s
  end

  it "reports a pending version: on disk, absent from schema_migrations" do
    dir = write_migrations("db/migrate", 20_260_101_000_000, 20_260_102_000_000)

    report = status(paths: [ dir ], applied: [ 20_260_101_000_000 ])
    path = report[:paths].first

    expect(path[:path]).to eq("db/migrate")
    expect(path[:pending]).to eq([ { version: "20260102000000", file: "20260102000000_change_20260102000000.rb", buried: false } ])
    expect(path[:pending_count]).to eq(1)
    expect(path[:pending_truncated]).to be(false)
    expect(path[:last_applied_version]).to eq("20260101000000")
  end

  it "marks a pending version OLDER than the highest applied one as buried" do
    dir = write_migrations("db/migrate", 20_260_101_000_000, 20_260_102_000_000, 20_260_103_000_000)

    report = status(paths: [ dir ], applied: [ 20_260_101_000_000, 20_260_103_000_000 ])
    path = report[:paths].first

    expect(path[:pending].map { |p| [ p[:version], p[:buried] ] }).to eq([ [ "20260102000000", true ] ])
    expect(path[:buried_count]).to eq(1)
  end

  it "does not call the newest pending version buried" do
    dir = write_migrations("db/migrate", 20_260_101_000_000, 20_260_105_000_000)

    path = status(paths: [ dir ], applied: [ 20_260_101_000_000 ])[:paths].first

    expect(path[:pending].first[:buried]).to be(false)
    expect(path[:buried_count]).to eq(0)
  end

  it "reports a version recorded in the database with no file on disk in ANY path" do
    a = write_migrations("db/migrate", 20_260_101_000_000)
    b = write_migrations("ext/db/migrate", 20_260_102_000_000)

    report = status(paths: [ a, b ], applied: [ 20_260_101_000_000, 20_260_102_000_000, 20_260_199_000_000 ])

    expect(report[:database][:db_only_versions]).to eq([ "20260199000000" ])
    expect(report[:database][:db_only_count]).to eq(1)
    expect(report[:database][:db_only_truncated]).to be(false)
    expect(report[:database][:highest_applied_version]).to eq("20260199000000")
  end

  it "does not call a version DB-only when a file for it lives in a different path" do
    a = write_migrations("db/migrate", 20_260_101_000_000)
    b = write_migrations("ext/db/migrate", 20_260_102_000_000)

    report = status(paths: [ a, b ], applied: [ 20_260_102_000_000 ])

    expect(report[:database][:db_only_versions]).to eq([])
  end

  it "flags a schema.rb header AHEAD of the database's highest applied version" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)
    schema = write_schema(20_260_301_000_000)

    report = status(paths: [ dir ], applied: [ 20_260_101_000_000 ], schema_path: schema)

    expect(report[:schema]).to include(present: true, file: "db/schema.rb", version: "20260301000000",
                                       ahead_of_database: true)
  end

  it "does not flag a schema header equal to, or behind, the database" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)
    schema = write_schema(20_260_101_000_000)

    expect(status(paths: [ dir ], applied: [ 20_260_101_000_000 ], schema_path: schema)[:schema][:ahead_of_database]).to be(false)
    expect(status(paths: [ dir ], applied: [ 20_260_101_000_000, 20_260_201_000_000 ], schema_path: schema)[:schema][:ahead_of_database]).to be(false)
  end

  it "reports a missing schema file as not present, not as ahead" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)

    report = status(paths: [ dir ], applied: [ 20_260_101_000_000 ], schema_path: root.join("db", "nope.rb").to_s)

    expect(report[:schema]).to include(present: false, version: nil, ahead_of_database: false)
  end

  it "reports a schema file with no parseable version header as present, with a nil version" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)
    schema = write_schema_text("# a dump with no define line\nActiveRecord::Schema.define do\nend\n")

    report = status(paths: [ dir ], applied: [ 20_260_101_000_000 ], schema_path: schema)

    expect(report[:schema]).to include(present: true, file: "db/schema.rb", version: nil, ahead_of_database: false)
  end

  it "reads an 8-digit (date-only) schema version, and an 8-digit migration version, as numbers" do
    dir = write_migrations("db/migrate", 20_260_101)
    schema = write_schema_text("ActiveRecord::Schema[8.1].define(version: 2026_02_01) do\nend\n")

    report = status(paths: [ dir ], applied: [], schema_path: schema)

    expect(report[:schema]).to include(present: true, version: "20260201", ahead_of_database: true)
    expect(report[:paths].first[:pending].map { |p| p[:version] }).to eq([ "20260101" ])
  end

  it "groups by migration path, each labelled relative to the root, with its own pending and last applied" do
    core = write_migrations("db/migrate", 20_260_101_000_000, 20_260_103_000_000)
    ext = write_migrations("vendor/ext/db/migrate", 20_260_102_000_000, 20_260_104_000_000)

    report = status(paths: [ core, ext ], applied: [ 20_260_101_000_000, 20_260_102_000_000 ])

    expect(report[:paths].map { |p| p[:path] }).to eq([ "db/migrate", "vendor/ext/db/migrate" ])
    expect(report[:paths].map { |p| p[:pending].map { |x| x[:version] } }).to eq([ [ "20260103000000" ], [ "20260104000000" ] ])
    expect(report[:paths].map { |p| p[:last_applied_version] }).to eq([ "20260101000000", "20260102000000" ])
    expect(report[:paths].map { |p| p[:file_count] }).to eq([ 2, 2 ])
  end

  describe "labelling a path outside the repository root" do
    around do |example|
      Dir.mktmpdir("migration-status-outside") do |dir|
        @outside = Pathname.new(dir)
        example.run
      end
    end

    let(:gem_root) { @outside.join("gems", "some-engine-1.0") }
    let(:gem_migrations) do
      gem_root.join("db", "migrate").tap do |dir|
        dir.mkpath
        dir.join("20260101000000_x.rb").write("# stub\n")
      end.to_s
    end

    it "uses external/<engine>/<path within the engine>, never an absolute or parent-relative path" do
      label = status(paths: [ gem_migrations ], applied: [], engine_roots: { gem_root.to_s => "some_engine" })[:paths].first[:path]

      expect(label).to eq("external/some_engine/db/migrate")
    end

    it "still emits a safe label when no engine owns the path" do
      label = status(paths: [ gem_migrations ], applied: [])[:paths].first[:path]

      expect(label).to start_with("external/")
      expect(label).not_to start_with("..")
      expect(label).not_to start_with("/")
      expect(label).not_to include(@outside.to_s)
    end

    it "labels a path inside the root relative to it" do
      inside = write_migrations("extensions/some-ext/server/db/migrate", 20_260_101_000_000)

      expect(status(paths: [ inside ], applied: [])[:paths].first[:path]).to eq("extensions/some-ext/server/db/migrate")
    end
  end

  it "counts a migration in a subdirectory, as Rails' own recursive glob does" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)
    nested = Pathname.new(dir).join("archive")
    nested.mkpath
    nested.join("20260102000000_nested.rb").write("# stub\n")

    path = status(paths: [ dir ], applied: [])[:paths].first

    expect(path[:file_count]).to eq(2)
    expect(path[:pending].map { |p| p[:version] }).to eq([ "20260101000000", "20260102000000" ])
  end

  it "reports a version found in more than one path as a duplicate, naming both paths" do
    a = write_migrations("db/migrate", 20_260_101_000_000, 20_260_102_000_000)
    b = write_migrations("ext/db/migrate", 20_260_102_000_000)

    report = status(paths: [ a, b ], applied: [])

    expect(report[:duplicate_versions]).to eq(
      [ { version: "20260102000000", paths: [ "db/migrate", "ext/db/migrate" ],
          files: [ "20260102000000_change_20260102000000.rb", "20260102000000_change_20260102000000.rb" ] } ]
    )
    expect(report[:duplicate_count]).to eq(1)
    expect(report[:duplicate_truncated]).to be(false)
  end

  it "reports no duplicates when every version is unique" do
    a = write_migrations("db/migrate", 20_260_101_000_000)
    b = write_migrations("ext/db/migrate", 20_260_102_000_000)

    expect(status(paths: [ a, b ], applied: [])[:duplicate_versions]).to eq([])
  end

  it "ignores non-migration files and returns basenames only" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)
    Pathname.new(dir).join("README.md").write("x")
    Pathname.new(dir).join("notes.rb").write("x")

    path = status(paths: [ dir ], applied: [])[:paths].first

    expect(path[:file_count]).to eq(1)
    expect(path[:pending].first[:file]).not_to include("/")
    expect(JSON.generate(status(paths: [ dir ], applied: []))).not_to include(root.to_s)
  end

  it "caps each list, reporting the full count and a truncated flag" do
    versions = (1..7).map { |n| 20_260_101_000_000 + n }
    dir = write_migrations("db/migrate", *versions)

    report = status(paths: [ dir ], applied: (1..7).map { |n| 20_260_201_000_000 + n }, limit: 3)
    path = report[:paths].first

    expect(path[:pending].size).to eq(3)
    expect(path[:pending_count]).to eq(7)
    expect(path[:pending_truncated]).to be(true)
    expect(report[:database][:db_only_versions].size).to eq(3)
    expect(report[:database][:db_only_count]).to eq(7)
    expect(report[:database][:db_only_truncated]).to be(true)
  end

  it "reports an empty database" do
    dir = write_migrations("db/migrate", 20_260_101_000_000)

    report = status(paths: [ dir ], applied: [])

    expect(report[:database]).to include(highest_applied_version: nil, applied_count: 0)
    expect(report[:paths].first[:last_applied_version]).to be_nil
    expect(report[:paths].first[:pending_count]).to eq(1)
  end

  describe ".current" do
    let(:migrate_paths) { Rails.application.config.paths["db/migrate"] }

    def repo_label(path)
      Pathname.new(path).relative_path_from(Rails.root.parent).to_s
    end

    it "reads the live connection once and derives its paths from Rails, not from a list" do
      report = described_class.current

      expect(report[:paths]).not_to be_empty
      expect(report[:database]).to include(:highest_applied_version, :applied_count, :db_only_versions)
      expect(report[:schema]).to include(:present, :ahead_of_database)
      expect(JSON.generate(report)).not_to include(Rails.root.to_s)
    end

    # The defect this pins: pool.migration_context.migrations_paths is
    # ["db/migrate"] outside rake (core only, cwd-relative); engines append to
    # config.paths["db/migrate"]. A core-only list also passes a "includes
    # db/migrate" assertion, so the assertion is over EVERY configured path,
    # with an extra engine path that only that list can supply.
    it "reports every path in config.paths['db/migrate'], engines included" do
      Dir.mktmpdir("migration-status-engine") do |dir|
        engine_root = Pathname.new(dir).join("extra-engine-1.0")
        extra = engine_root.join("db", "migrate")
        extra.mkpath
        extra.join("29990101000000_from_the_extra_engine.rb").write("# stub\n")

        configured = migrate_paths.expanded
        allow(migrate_paths).to receive(:expanded).and_return([ *configured, extra.to_s ])

        report = described_class.current
        labels = report[:paths].map { |p| p[:path] }

        configured.each do |path|
          expect(labels).to include(repo_label(path)), "#{path} is configured but absent from the report"
        end
        expect(report[:paths].size).to eq(configured.size + 1)
        extra_entry = report[:paths].find { |p| p[:pending].any? { |x| x[:version] == "29990101000000" } }
        expect(extra_entry).not_to be_nil
        expect(extra_entry[:path]).to start_with("external/")
      end
    end

    it "emits no label that starts with '..' or '/'" do
      labels = described_class.current[:paths].map { |p| p[:path] }

      expect(labels).to all(satisfy { |label| !label.start_with?("..", "/") })
    end
  end
end

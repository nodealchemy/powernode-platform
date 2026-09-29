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

  def status(paths:, applied:, schema_path: nil, limit: described_class::LIST_LIMIT)
    described_class.new(migrations_paths: paths, applied_versions: applied, schema_path: schema_path,
                        root: root, limit: limit).report
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

  it "groups by migration path, each labelled relative to the root, with its own pending and last applied" do
    core = write_migrations("db/migrate", 20_260_101_000_000, 20_260_103_000_000)
    ext = write_migrations("vendor/ext/db/migrate", 20_260_102_000_000, 20_260_104_000_000)

    report = status(paths: [ core, ext ], applied: [ 20_260_101_000_000, 20_260_102_000_000 ])

    expect(report[:paths].map { |p| p[:path] }).to eq([ "db/migrate", "vendor/ext/db/migrate" ])
    expect(report[:paths].map { |p| p[:pending].map { |x| x[:version] } }).to eq([ [ "20260103000000" ], [ "20260104000000" ] ])
    expect(report[:paths].map { |p| p[:last_applied_version] }).to eq([ "20260101000000", "20260102000000" ])
    expect(report[:paths].map { |p| p[:file_count] }).to eq([ 2, 2 ])
  end

  it "labels a path outside the root without leaking an absolute path" do
    outside = Dir.mktmpdir("migration-status-outside")
    Pathname.new(outside).join("20260101000000_x.rb").write("# stub\n")

    label = status(paths: [ outside ], applied: [])[:paths].first[:path]

    expect(label).not_to start_with("/")
    expect(label).to include("..")
  ensure
    FileUtils.rm_rf(outside) if outside
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
    it "reads the live connection once and derives its paths from Rails, not from a list" do
      report = described_class.current

      expect(report[:paths]).not_to be_empty
      expect(report[:paths].map { |p| p[:path] }).to include("db/migrate")
      expect(report[:database]).to include(:highest_applied_version, :applied_count, :db_only_versions)
      expect(report[:schema]).to include(:present, :ahead_of_database)
      expect(JSON.generate(report)).not_to include(Rails.root.to_s)
    end
  end
end

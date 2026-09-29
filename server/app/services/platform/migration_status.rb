# frozen_string_literal: true

require "pathname"

module Platform
  # Migration state as a read (IMP-d421e10d4677), so an operator does not have
  # to open psql to compare schema_migrations with the files on disk. Two
  # outages were migration-shaped and neither was visible from any tool: a
  # raising data migration crash-looped rails at boot, and a schema.rb version
  # bump buried extension migrations as stamped-but-not-run.
  #
  # ── WHAT IS REPORTED, AND AT WHAT LEVEL ─────────────────────────────────
  #
  # Per migration path (the paths Rails itself resolved, engine-appended ones
  # included): the file count, the last applied version among ITS files, and its
  # pending versions. schema_migrations is one table for the whole database, so
  # the rest is database-level and is NOT attributable to a path: the highest
  # applied version, and the versions recorded with no file in ANY path.
  #
  # `buried` is the dangerous pending shape: a pending version OLDER than the
  # database's highest applied one. A migrator that only runs forward will skip
  # it, and a schema:load of a header at or past it stamps it applied without
  # ever running it. Pending versions are listed oldest first, so the buried
  # ones survive the list cap.
  #
  # `schema.ahead_of_database` is the file-versus-database comparison the
  # incident needed: the header of the schema file Rails would load is newer
  # than anything the database has applied.
  #
  # ── WHAT IS NOT REPORTED ────────────────────────────────────────────────
  #
  # Version numbers and file basenames only: no SQL, no row data, no migration
  # class loaded, and no absolute path. A path is labelled relative to the app
  # root, so it names an extension only when the deployment actually has one
  # and only in the response, never in this source.
  class MigrationStatus
    LIST_LIMIT = 50
    SCHEMA_HEADER_LINES = 60
    SCHEMA_VERSION_PATTERN = /\.define\(\s*version:\s*([\d_]+)/

    # The live connection, read once: the applied set comes from a single
    # schema_migrations read and the paths from the pool's migration context,
    # which is what db:migrate itself walks.
    def self.current(pool: ActiveRecord::Base.connection_pool, root: Rails.root)
      context = pool.migration_context
      new(
        migrations_paths: context.migrations_paths,
        applied_versions: context.get_all_versions,
        schema_path: ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(pool.db_config),
        root: root
      ).report
    end

    def initialize(migrations_paths:, applied_versions:, schema_path:, root:, limit: LIST_LIMIT)
      @migrations_paths = Array(migrations_paths).map(&:to_s).uniq
      @applied = applied_versions.map(&:to_i).to_set
      @schema_path = schema_path
      @root = Pathname.new(root.to_s)
      @limit = limit
    end

    def report
      files_by_path = @migrations_paths.to_h { |path| [ path, migration_files(path) ] }
      highest = @applied.max

      {
        database: database_section(files_by_path, highest),
        schema: schema_section(highest),
        paths: files_by_path.map { |path, files| path_section(path, files, highest) }
      }
    end

    private

    # [ [version_integer, basename], ... ] sorted oldest first. Filenames only —
    # the same pattern Rails uses, so a file Rails would not treat as a
    # migration is not counted here either.
    def migration_files(path)
      return [] unless File.directory?(path)

      Dir.children(path).filter_map do |name|
        match = ActiveRecord::Migration::MigrationFilenameRegexp.match(name)
        [ match[1].to_i, name ] if match
      end.sort
    end

    def database_section(files_by_path, highest)
      on_disk = files_by_path.values.flat_map { |files| files.map(&:first) }.to_set
      db_only = (@applied - on_disk).sort

      {
        highest_applied_version: version_string(highest),
        applied_count: @applied.size,
        db_only_versions: db_only.first(@limit).map(&:to_s),
        db_only_count: db_only.size,
        db_only_truncated: db_only.size > @limit
      }
    end

    def path_section(path, files, highest)
      pending = files.reject { |version, _| @applied.include?(version) }
      buried = highest ? pending.count { |version, _| version < highest } : 0
      last_applied = files.map(&:first).select { |version| @applied.include?(version) }.max

      {
        path: label(path),
        file_count: files.size,
        last_applied_version: version_string(last_applied),
        pending: pending.first(@limit).map do |version, name|
          { version: version.to_s, file: name, buried: !highest.nil? && version < highest }
        end,
        pending_count: pending.size,
        pending_truncated: pending.size > @limit,
        buried_count: buried
      }
    end

    def schema_section(highest)
      version = schema_header_version
      {
        present: !version.nil?,
        file: @schema_path && label(@schema_path),
        version: version_string(version),
        ahead_of_database: !version.nil? && version > (highest || 0)
      }
    end

    # Only the define(version:) line. The file is a dump, potentially large; the
    # header sits in its first few lines, so stop reading there.
    def schema_header_version
      return nil if @schema_path.blank? || !File.file?(@schema_path)

      File.foreach(@schema_path).first(SCHEMA_HEADER_LINES).each do |line|
        match = SCHEMA_VERSION_PATTERN.match(line)
        return match[1].delete("_").to_i if match
      end
      nil
    end

    def label(path)
      Pathname.new(path).expand_path.relative_path_from(@root.expand_path).to_s
    rescue ArgumentError
      File.basename(path.to_s)
    end

    def version_string(version)
      version&.to_s
    end
  end
end

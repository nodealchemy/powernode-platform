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
  # Per migration path (Rails.application.config.paths["db/migrate"], the list
  # engines append to, so extension migrations are included): the file count, the last applied version among ITS files, and its
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
  # class loaded, and no absolute path. A path inside the repository is labelled
  # relative to the repository root; one outside it (a gem engine) is labelled
  # external/<engine>/<path within the engine>, so the host's directory layout
  # never leaves the process. A label names an extension only when the
  # deployment actually has one, and only in the response, never in this source.
  #
  # ── WHY NOT pool.migration_context.migrations_paths ─────────────────────
  #
  # Outside rake that is Migrator.migrations_paths — ["db/migrate"], relative,
  # core only and cwd-dependent. Only databases.rake copies the engine paths in.
  # Reading it made every applied extension version look db_only and hid a buried
  # extension migration, which is the incident this exists for. The connection is
  # still the primary one; only the path list comes from the application config.
  class MigrationStatus
    LIST_LIMIT = 50
    SCHEMA_HEADER_LINES = 60
    SCHEMA_VERSION_PATTERN = /\.define\(\s*version:\s*([\d_]+)/

    # The live connection, read once: the applied set comes from a single
    # schema_migrations read, the paths from the application config (engines
    # included), and the labels are relative to the repository root, the parent
    # of the Rails app directory.
    def self.current(pool: ActiveRecord::Base.connection_pool, root: Rails.root.parent)
      new(
        migrations_paths: Rails.application.config.paths["db/migrate"].expanded,
        applied_versions: pool.migration_context.get_all_versions,
        schema_path: ActiveRecord::Tasks::DatabaseTasks.schema_dump_path(pool.db_config),
        root: root,
        engine_roots: engine_roots
      ).report
    end

    # { engine root => engine name } for every engine the application loaded,
    # so a path outside the repository can be named by its engine.
    def self.engine_roots
      Rails.application.railties.select { |railtie| railtie.is_a?(Rails::Engine) }
           .to_h { |engine| [ engine.root.to_s, engine.engine_name ] }
    end

    def initialize(migrations_paths:, applied_versions:, schema_path:, root:, limit: LIST_LIMIT, engine_roots: {})
      @migrations_paths = Array(migrations_paths).map(&:to_s).uniq
      @applied = applied_versions.map(&:to_i).to_set
      @schema_path = schema_path
      @root = Pathname.new(root.to_s).expand_path
      @limit = limit
      @engine_roots = engine_roots.transform_keys { |path| Pathname.new(path.to_s).expand_path }
    end

    def report
      files_by_path = @migrations_paths.to_h { |path| [ path, migration_files(path) ] }
      highest = @applied.max
      duplicates = duplicate_versions(files_by_path)

      {
        database: database_section(files_by_path, highest),
        schema: schema_section(highest),
        paths: files_by_path.map { |path, files| path_section(path, files, highest) },
        duplicate_versions: duplicates.first(@limit),
        duplicate_count: duplicates.size,
        duplicate_truncated: duplicates.size > @limit
      }
    end

    private

    # [ [version_integer, basename], ... ] sorted oldest first. Filenames only.
    # The same recursive glob and filename pattern Rails uses, so a file Rails
    # would not treat as a migration is not counted here either.
    def migration_files(path)
      return [] unless File.directory?(path)

      Dir[File.join(path, "**", "[0-9]*_*.rb")].filter_map do |file|
        name = File.basename(file)
        match = ActiveRecord::Migration::MigrationFilenameRegexp.match(name)
        [ match[1].to_i, name ] if match
      end.sort
    end

    # A version present in more than one file. Rails refuses to migrate over one
    # (DuplicateMigrationVersionError), and the duplicate can span two paths.
    def duplicate_versions(files_by_path)
      entries = files_by_path.flat_map do |path, files|
        files.map { |version, name| [ version, label(path), name ] }
      end

      entries.group_by(&:first).select { |_, group| group.size > 1 }.sort.map do |version, group|
        { version: version.to_s, paths: group.map { |e| e[1] }.uniq, files: group.map { |e| e[2] } }
      end
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
        present: !@schema_path.blank? && File.file?(@schema_path),
        file: @schema_path.presence && label(@schema_path),
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

    # Relative to the repository root when inside it; otherwise
    # external/<engine>/<path within the engine>, or external/<basename> when no
    # engine owns the path. Never absolute, never "..": relative_path_from would
    # happily print ../../usr/local/... for a gem engine.
    def label(path)
      absolute = Pathname.new(path).expand_path
      return absolute.relative_path_from(@root).to_s if inside?(absolute, @root)

      engine_root, engine_name = @engine_roots.select { |root, _| inside?(absolute, root) }.max_by { |root, _| root.to_s.length }
      return File.join("external", engine_name, absolute.relative_path_from(engine_root).to_s) if engine_root

      File.join("external", absolute.basename.to_s)
    end

    def inside?(path, root)
      path == root || path.to_s.start_with?("#{root}/")
    end

    def version_string(version)
      version&.to_s
    end
  end
end

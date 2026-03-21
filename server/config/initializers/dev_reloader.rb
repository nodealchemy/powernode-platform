# frozen_string_literal: true

# Development file watcher — restarts Puma when Ruby source files change.
#
# Rails' built-in code reloading (config.enable_reloading) is disabled to
# prevent interlock deadlocks with long-lived SSE streams. This watcher
# restores the development experience by monitoring source files and
# sending SIGUSR2 to trigger a full Puma restart (re-exec).
#
# Why SIGUSR2 instead of `plugin :tmp_restart`:
#   The tmp_restart plugin runs a one-shot polling loop that exits after
#   the first restart attempt. If any file changes early in the process
#   lifetime, subsequent changes go unnoticed. SIGUSR2 uses Puma's signal
#   handler which remains active for the entire process lifetime.
#
# Watched directories:
#   - server/app, server/config, server/lib (core)
#   - extensions/*/server/app, extensions/*/server/config (extension engines)

if Rails.env.development?
  Thread.new do
    Thread.current.name = "dev-reloader"

    watch_dirs = %w[app config lib].map { |d| Rails.root.join(d).to_s }
    # Watch both app/ and config/ in extensions (routes.rb changes need restart too)
    %w[app config].each do |subdir|
      Dir.glob(Rails.root.join("..", "extensions", "*", "server", subdir).to_s).each do |ext_dir|
        watch_dirs << ext_dir if File.directory?(ext_dir)
      end
    end

    last_change_at = nil

    # Build initial snapshot of mtimes
    snapshot = {}
    watch_dirs.each do |dir|
      Dir.glob("#{dir}/**/*.rb").each do |f|
        snapshot[f] = File.mtime(f) rescue nil
      end
    end

    Rails.logger.info "[DevReloader] Watching #{watch_dirs.size} directories (#{snapshot.size} files)"

    loop do
      sleep 2
      changed = false
      changed_files = []

      watch_dirs.each do |dir|
        Dir.glob("#{dir}/**/*.rb").each do |f|
          mtime = File.mtime(f) rescue nil
          if mtime && snapshot[f] != mtime
            snapshot[f] = mtime
            changed = true
            changed_files << f
          end
        end
      end

      # Debounce: reset timer on every change, restart only after 10s of quiet
      if changed
        last_change_at = Time.now
        @pending_changed_files = ((@pending_changed_files || []) + changed_files).uniq.last(10)
      end

      next unless last_change_at && (Time.now - last_change_at) >= 10

      last_change_at = nil
      pending = @pending_changed_files || []
      @pending_changed_files = []

      # Clear bootsnap iseq cache before restart — Puma re-execs the Ruby
      # process directly (bypassing the shell wrapper), so extension bytecode
      # would otherwise be served from stale cache.
      iseq_cache = Rails.root.join("tmp", "cache", "bootsnap", "compile-cache-iseq")
      FileUtils.rm_rf(iseq_cache) if iseq_cache.exist?

      short_names = pending.map { |f| f.sub("#{Rails.root}/", "").sub(%r{.*/extensions/}, "ext/") }
      Rails.logger.info "[DevReloader] Source files changed — restarting Puma via SIGUSR2 (#{short_names.join(', ')})"

      # SIGUSR2 triggers Puma's built-in restart (re-exec). Unlike tmp_restart,
      # this signal handler remains active for the entire process lifetime.
      Process.kill(:USR2, Process.pid)
    rescue StandardError => e
      Rails.logger.warn "[DevReloader] File watcher error: #{e.message}"
      sleep 5
    end
  end
end

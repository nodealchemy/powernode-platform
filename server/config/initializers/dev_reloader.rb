# frozen_string_literal: true

# Development file watcher — restarts Puma when Ruby source files change.
#
# Rails' built-in code reloading (config.enable_reloading) is disabled to
# prevent interlock deadlocks with long-lived SSE streams. This watcher
# restores the development experience by monitoring source files and
# triggering Puma's `plugin :tmp_restart` when changes are detected.
#
# Watched directories:
#   - server/app, server/config, server/lib (core)
#   - extensions/*/server/app (extension engines)

if Rails.env.development?
  Thread.new do
    Thread.current.name = "dev-reloader"
    restart_file = Rails.root.join("tmp", "restart.txt")

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

      watch_dirs.each do |dir|
        Dir.glob("#{dir}/**/*.rb").each do |f|
          mtime = File.mtime(f) rescue nil
          if mtime && snapshot[f] != mtime
            snapshot[f] = mtime
            changed = true
          end
        end
      end

      # Debounce: reset timer on every change, restart only after 5s of quiet
      last_change_at = Time.now if changed

      next unless last_change_at && (Time.now - last_change_at) >= 5

      last_change_at = nil

      # Clear bootsnap iseq cache before restart — Puma re-execs the Ruby
      # process directly (bypassing the shell wrapper), so extension bytecode
      # would otherwise be served from stale cache.
      iseq_cache = Rails.root.join("tmp", "cache", "bootsnap", "compile-cache-iseq")
      FileUtils.rm_rf(iseq_cache) if iseq_cache.exist?

      Rails.logger.info "[DevReloader] Source files changed — triggering Puma restart (bootsnap cache cleared)"
      FileUtils.touch(restart_file)
    rescue StandardError => e
      Rails.logger.warn "[DevReloader] File watcher error: #{e.message}"
      sleep 5
    end
  end
end

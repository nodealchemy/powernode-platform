# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.

# Threads per worker process. Each thread can handle one request concurrently.
# With GVL, threads help most with IO-bound work (DB queries, HTTP calls).
max_threads_count = ENV.fetch("RAILS_MAX_THREADS", 16).to_i
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { [max_threads_count / 2, 4].max }.to_i
threads min_threads_count, max_threads_count

# Worker processes multiply throughput by bypassing the GVL.
# Each worker forks the app and gets its own thread pool + DB pool.
# In development, run single-process (workers 0) to avoid deadlocks
# between forked workers and Zeitwerk code reloading.
web_concurrency = ENV.fetch("WEB_CONCURRENCY", 0).to_i

if web_concurrency > 0
  # Multi-worker mode — each worker forks the app and gets its own
  # thread pool + DB pool. Workers are independently recyclable, preventing
  # memory bloat from affecting the entire process.
  workers web_concurrency
  preload_app!

  # Draw routes in the master before forking. With eager_load=false Rails
  # defers route drawing to the first request (LazyRouteSet), and
  # RoutesReloader#execute_unless_loaded sets @loaded=true BEFORE the
  # multi-second draw finishes with no lock — concurrent first requests in a
  # fresh worker match against a partially-built route set and 404 real
  # routes (e.g. /api/v1/mcp/message after every SIGUSR2 hot restart, which
  # made MCP clients drop the server). Drawing once here means every forked
  # worker inherits the complete route set.
  before_fork do
    Rails.application.reload_routes_unless_loaded if defined?(Rails) && Rails.application
  end
else
  workers 0
end

# Force-kill threads after 5s during restart. SSE streams (MCP, A2A) hold
# threads indefinitely; without this, Puma waits forever during restart.
force_shutdown_after 5

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Dev restarts are handled by SIGUSR2 via Claude Code hooks (see
# .claude/hooks/service-restart-apply.sh) or manually via scripts/reload-backend.sh.

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Re-establish DB connections after fork (required with preload_app!)
if web_concurrency > 0
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)

    # Worker recycler: restart this worker after MAX_WORKER_AGE or when RSS exceeds
    # MAX_WORKER_RSS. Puma phased-restart replaces workers one at a time, so there's
    # no downtime. This prevents memory bloat from long-running trading context assembly.
    max_age = ENV.fetch("MAX_WORKER_AGE", 3600).to_i     # 1 hour default
    max_rss_mb = ENV.fetch("MAX_WORKER_RSS_MB", 800).to_i # 800MB default
    worker_booted_at = Time.now

    Thread.new do
      loop do
        sleep 60
        age = Time.now - worker_booted_at
        rss_kb = `ps -o rss= -p #{Process.pid}`.strip.to_i rescue 0
        rss_mb = rss_kb / 1024

        if age > max_age
          $stdout.puts "[Puma] Worker #{Process.pid} recycling: age #{(age / 60).round}min > #{max_age / 60}min limit"
          Process.kill(:QUIT, Process.pid)
          break
        elsif rss_mb > max_rss_mb
          $stdout.puts "[Puma] Worker #{Process.pid} recycling: RSS #{rss_mb}MB > #{max_rss_mb}MB limit"
          Process.kill(:QUIT, Process.pid)
          break
        end
      end
    end
  end
end

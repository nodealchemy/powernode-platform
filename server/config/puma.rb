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
if ENV.fetch("RAILS_ENV", "development") == "development"
  workers 0
  # Force-kill threads after 5s during restart. SSE streams (MCP, A2A) hold
  # threads indefinitely; without this, Puma waits forever during restart.
  force_shutdown_after 5
else
  workers ENV.fetch("WEB_CONCURRENCY", 2).to_i
  preload_app!
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Dev restarts are handled by SIGUSR2 from config/initializers/dev_reloader.rb.
# The tmp_restart plugin is intentionally NOT used — its one-shot polling loop
# exits after the first restart attempt, making it unreliable for automated
# file watchers that may trigger multiple times during a process lifetime.

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# Re-establish DB connections after fork (required with preload_app!)
if ENV.fetch("RAILS_ENV", "development") != "development"
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
end

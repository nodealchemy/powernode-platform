# frozen_string_literal: true

module Platform
  module Health
    # THE ONE SET OF CORE SERVICE CHECKS: database, redis, sidekiq, disk,
    # memory and cpu, each a small reading with a `status` of healthy, warning,
    # unhealthy or unknown.
    #
    # The maintenance health endpoint, Ai::MonitoringHealthService and the
    # core_service status contributor all read these. Each used to carry its
    # own copy, and the copies had drifted (one timed the database, one read
    # the pool, one reported a sidekiq with no workers as healthy).
    #
    # `unknown` means "could not read it", and is never reported as healthy: a
    # host where /proc is missing is unmeasured, not fine.
    #
    # ── WHAT A READING MAY CARRY ────────────────────────────────────────────
    # The readings land on shared status rows that every member can see, so a
    # failure carries the exception CLASS and the message goes to the log; a
    # success carries counts, never a queue name or a memory figure.
    module CoreChecks
      SERVICES = %i[database redis sidekiq disk memory cpu].freeze

      # Same thresholds the maintenance page has always used.
      DISK_WARNING_PERCENT = 80
      MEMORY_WARNING_PERCENT = 80
      LOAD_WARNING = 2.0

      # A Sidekiq process heartbeats every few seconds; one silent for longer
      # than this has crashed, even though its identity stays registered until
      # something prunes it.
      LIVE_BEAT_SECONDS = 60

      module_function

      # @return [Hash{Symbol=>Hash}] each reading, in SERVICES order
      def all
        SERVICES.index_with { |service| public_send(service) }
      end

      # Also the database's name, size and active connections. Each of those is
      # read on its own: one the role may not read is absent with a reason,
      # never a 0, and the database is still healthy.
      def database
        connection = ActiveRecord::Base.connection
        started = monotonic_now
        connection.execute("SELECT 1")
        response_time_ms = elapsed_ms(started)
        pool = ActiveRecord::Base.connection_pool.stat

        {
          status: "healthy",
          response_time_ms: response_time_ms,
          connection_pool: pool.slice(:size, :connections, :busy, :idle),
          database: connection.current_database
        }.merge(
          figure(:size_bytes) { connection.select_value("SELECT pg_database_size(current_database())") },
          figure(:active_connections) do
            connection.select_value(
              "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND state = 'active'"
            )
          end
        )
      rescue StandardError => e
        failure("unhealthy", :database, e)
      end

      # Reads the app's memoized client unless handed one, so a check opens no
      # connection of its own.
      def redis(client: ::Powernode::Redis.client)
        started = monotonic_now
        client.ping
        response_time_ms = elapsed_ms(started)

        {
          status: "healthy",
          response_time_ms: response_time_ms,
          connected_clients: client.info["connected_clients"].to_i,
          cache_store: cache_store
        }
      rescue StandardError => e
        failure("unhealthy", :redis, e).merge(cache_store: cache_store)
      end

      # The configured Rails cache store's class, read in-process, so it is
      # known even when Redis is not. Never its URL or host.
      def cache_store
        Rails.cache.class.name
      end

      # Sidekiq runs in the standalone worker app and this app stays
      # Sidekiq-free, so its state is read from the process registry and the
      # counters Sidekiq keeps in the worker's Redis — never through the gem.
      # Only an identity whose heartbeat is recent counts as a worker: a
      # crashed one stays in `processes` until pruned. A Redis we cannot read
      # tells us nothing about Sidekiq: unknown, not unhealthy.
      def sidekiq
        client = ::Powernode::Redis.new_worker_client
        beats = client.smembers("processes").map { |identity| client.hget(identity, "beat").presence&.to_f }
        live = beats.compact.count { |beat| beat >= Time.current.to_f - LIVE_BEAT_SECONDS }
        queues = client.smembers("queues")

        {
          status: live.positive? ? "healthy" : "unhealthy",
          processes: live,
          stale_processes: beats.size - live,
          processed: client.get("stat:processed").to_i,
          failed: client.get("stat:failed").to_i,
          enqueued: queues.sum { |queue| client.llen("queue:#{queue}") },
          queue_count: queues.size
        }.merge(last_seen(beats))
      rescue StandardError => e
        failure("unknown", :sidekiq, e)
      ensure
        client&.close
      end

      # The newest heartbeat, absent when no identity carries one.
      def last_seen(beats)
        newest = beats.compact.max
        newest ? { last_seen_at: Time.at(newest).utc.iso8601 } : {}
      end

      # { key => Integer } when the query answers; otherwise { "<key>_reason" =>
      # the exception class }, with the message logged, not returned.
      def figure(key)
        value = yield
        return { "#{key}_reason": "query returned no value" } if value.nil?

        { key => value.to_i }
      rescue StandardError => e
        Rails.logger.warn "[CoreChecks] #{key} could not be read: #{e.class}: #{e.message}"
        { "#{key}_reason": e.class.name }
      end

      def failure(status, service, error)
        Rails.logger.warn "[CoreChecks] #{service} check failed: #{error.class}: #{error.message}"
        { status: status, error_class: error.class.name }
      end

      def disk
        stat = ::Sys::Filesystem.stat("/")
        used_percentage = ((1 - (stat.bytes_free.to_f / stat.bytes_total)) * 100).round(2)

        {
          status: used_percentage < DISK_WARNING_PERCENT ? "healthy" : "warning",
          used_percentage: used_percentage,
          free_gb: (stat.bytes_free / 1.gigabyte).round(2)
        }
      rescue StandardError => e
        Rails.logger.warn "[CoreChecks] disk not readable: #{e.class}: #{e.message}"
        { status: "unknown" }
      end

      # From /proc/meminfo: used = MemTotal - MemAvailable.
      def memory
        meminfo = File.read("/proc/meminfo")
        total_kb = meminfo[/^MemTotal:\s+(\d+)/, 1].to_f
        available_kb = meminfo[/^MemAvailable:\s+(\d+)/, 1].to_f
        raise ArgumentError, "MemTotal missing" unless total_kb.positive?

        used_kb = total_kb - available_kb
        used_percentage = ((used_kb / total_kb) * 100).round(2)

        {
          status: used_percentage < MEMORY_WARNING_PERCENT ? "healthy" : "warning",
          used_percentage: used_percentage,
          used_mb: (used_kb / 1024).round,
          total_mb: (total_kb / 1024).round
        }
      rescue StandardError => e
        Rails.logger.warn "[CoreChecks] memory not readable: #{e.class}: #{e.message}"
        { status: "unknown" }
      end

      # From /proc/loadavg.
      def cpu
        one, five, fifteen = File.read("/proc/loadavg").split.first(3).map(&:to_f)

        {
          status: one < LOAD_WARNING ? "healthy" : "warning",
          load_1min: one,
          load_5min: five,
          load_15min: fifteen
        }
      rescue StandardError => e
        Rails.logger.warn "[CoreChecks] load average not readable: #{e.class}: #{e.message}"
        { status: "unknown" }
      end

      def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def elapsed_ms(started) = ((monotonic_now - started) * 1000).round(2)
    end
  end
end

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
    module CoreChecks
      SERVICES = %i[database redis sidekiq disk memory cpu].freeze

      # Same thresholds the maintenance page has always used.
      DISK_WARNING_PERCENT = 80
      MEMORY_WARNING_PERCENT = 80
      LOAD_WARNING = 2.0

      module_function

      # @return [Hash{Symbol=>Hash}] every service's reading, in SERVICES order
      def all
        SERVICES.index_with { |service| public_send(service) }
      end

      def database
        started = monotonic_now
        ActiveRecord::Base.connection.execute("SELECT 1")
        pool = ActiveRecord::Base.connection_pool.stat

        {
          status: "healthy",
          response_time_ms: elapsed_ms(started),
          connection_pool: pool.slice(:size, :connections, :busy, :idle)
        }
      rescue StandardError => e
        { status: "unhealthy", error: e.message }
      end

      def redis
        client = ::Powernode::Redis.new_client
        started = monotonic_now
        client.ping
        response_time_ms = elapsed_ms(started)
        info = client.info

        {
          status: "healthy",
          response_time_ms: response_time_ms,
          used_memory: info["used_memory_human"],
          connected_clients: info["connected_clients"].to_i
        }
      rescue StandardError => e
        { status: "unhealthy", error: e.message }
      end

      # Sidekiq runs in the standalone worker app and this app stays
      # Sidekiq-free, so its state is read from the process registry and the
      # counters Sidekiq keeps in the worker's Redis — never through the gem.
      # No registered process means nothing is working the queues, however
      # healthy the counters look. A Redis we cannot read tells us nothing
      # about Sidekiq: unknown, not unhealthy.
      def sidekiq
        client = ::Powernode::Redis.new_worker_client
        processes = client.smembers("processes")
        queues = client.smembers("queues").sort.index_with { |queue| client.llen("queue:#{queue}") }

        {
          status: processes.any? ? "healthy" : "unhealthy",
          processes: processes.size,
          processed: client.get("stat:processed").to_i,
          failed: client.get("stat:failed").to_i,
          enqueued: queues.values.sum,
          queues: queues
        }
      rescue StandardError => e
        { status: "unknown", error: e.message }
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

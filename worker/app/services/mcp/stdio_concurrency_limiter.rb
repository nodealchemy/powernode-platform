# frozen_string_literal: true

module Mcp
  # IMP-ecc0e18c0455 — caps how many synchronous stdio MCP executions
  # (POST /api/v1/mcp/execute_stdio, JobsController#execute_stdio_mcp) run
  # at once in this worker-web process.
  #
  # Each of those calls holds a Puma request thread for its whole deadline
  # (up to McpSecurityService::MAX_STDIO_TIMEOUT_SECONDS plus the TERM
  # grace), and worker-web's pool is shared with the LLM proxy, streaming
  # and embeddings. Without a cap, slow or hung MCP servers can hold every
  # thread and starve all of those platform-wide.
  #
  # The cap never queues: #try_acquire answers immediately, so a refused
  # call costs its thread microseconds instead of parking it behind a slot
  # (parking would be the very starvation this exists to prevent). The
  # caller MUST pair a successful #try_acquire with #release in an
  # `ensure`.
  #
  # PER PROCESS. The counter lives in this process's memory. worker-web is
  # launched as a single Puma process (`rackup -s puma -O Threads=0:N`, no
  # workers, in both scripts/systemd/powernode-worker-web.sh and the hub
  # worker module's start script), so today this is the whole cap. Were
  # worker-web ever run in Puma cluster mode, each worker process would
  # get its own counter and the effective cap would be limit x workers.
  # The Sidekiq process never serves this endpoint; its async MCP jobs are
  # bounded by Sidekiq's own concurrency, not by this.
  class StdioConcurrencyLimiter
    ENV_KEY = 'MCP_STDIO_MAX_CONCURRENCY'

    # Half of the default 16-thread pool: with every slot held for the
    # worst case, 8 threads are still free for LLM, streaming and
    # embedding requests.
    DEFAULT_LIMIT = 8

    # The pool size both launch scripts default WORKER_WEB_THREADS to. They
    # assign it as a plain shell variable, so this process only sees
    # WORKER_WEB_THREADS in ENV when the operator set it (the service
    # environment exports it); otherwise the scripts' own default applies,
    # which is this number.
    WEB_THREADS_ENV_KEY = 'WORKER_WEB_THREADS'
    DEFAULT_WEB_THREADS = 16

    # A cap at or above the pool size is no cap. Whatever is configured,
    # this many threads stay out of reach of stdio MCP calls (on a pool
    # too small to afford that, the cap bottoms out at 1).
    RESERVED_WEB_THREADS = 4

    INSTANCE_LOCK = Mutex.new
    private_constant :INSTANCE_LOCK

    class << self
      # The one limiter this process shares across request threads,
      # resolved from ENV on first use (config.ru touches it at boot, so a
      # bad value is reported in the boot log rather than on first call).
      def instance
        INSTANCE_LOCK.synchronize do
          @instance ||= new(limit: resolve_limit(logger: PowernodeWorker.application.logger))
        end
      end

      # Specs only: drop the memoized instance so the next .instance
      # resolves afresh.
      def reset_instance!
        INSTANCE_LOCK.synchronize { @instance = nil }
      end

      # The effective cap. Unset or blank means DEFAULT_LIMIT. Anything
      # but a positive decimal integer (a word, a fraction, zero, a
      # negative) is ignored for the default, with a warning: zero must not
      # silently switch synchronous stdio MCP off, and a typo must not
      # switch the cap off. A value above the ceiling is clamped to it,
      # with a warning. The rejected text itself is never logged.
      def resolve_limit(env: ENV, logger: nil)
        ceiling = [ web_threads(env) - RESERVED_WEB_THREADS, 1 ].max
        raw = env[ENV_KEY].to_s.strip
        return [ DEFAULT_LIMIT, ceiling ].min if raw.empty?

        value = Integer(raw, 10, exception: false)
        unless value&.positive?
          fallback = [ DEFAULT_LIMIT, ceiling ].min
          logger&.warn "#{ENV_KEY} is not a positive integer; using the default of #{fallback}"
          return fallback
        end

        if value > ceiling
          logger&.warn "#{ENV_KEY}=#{value} would not leave #{RESERVED_WEB_THREADS} of worker-web's " \
                       "#{web_threads(env)} threads for other requests; clamped to #{ceiling}"
          return ceiling
        end

        value
      end

      private

      def web_threads(env)
        value = Integer(env[WEB_THREADS_ENV_KEY].to_s.strip, 10, exception: false)
        value&.positive? ? value : DEFAULT_WEB_THREADS
      end
    end

    attr_reader :limit

    def initialize(limit:)
      raise ArgumentError, 'limit must be a positive Integer' unless limit.is_a?(Integer) && limit.positive?

      @limit = limit
      @in_flight = 0
      @rejected_total = 0
      @lock = Mutex.new
    end

    # Takes a slot if one is free. Never waits: false means the cap is full
    # right now.
    def try_acquire
      @lock.synchronize do
        if @in_flight < @limit
          @in_flight += 1
          true
        else
          @rejected_total += 1
          false
        end
      end
    end

    # Gives back a slot taken by a successful #try_acquire.
    def release
      @lock.synchronize { @in_flight -= 1 if @in_flight.positive? }
      nil
    end

    def in_flight
      @lock.synchronize { @in_flight }
    end

    # Calls refused since this process started, for the saturation log line.
    def rejected_total
      @lock.synchronize { @rejected_total }
    end
  end
end

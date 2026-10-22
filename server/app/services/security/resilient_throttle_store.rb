# frozen_string_literal: true

module Security
  # The store Rack::Attack counts throttles in when Redis is configured.
  #
  # Counts go to Redis (shared by every process) while Redis answers. On a
  # Redis error they go to a per-process MemoryStore instead, so throttles keep
  # tripping, only not shared across processes, rather than failing open: a
  # RedisCacheStore answers nil on an error, and Rack::Attack then reports a
  # count of 1 for every request, which turned off the login, 2FA,
  # password-reset and node claim/enroll throttles whenever Redis was down.
  #
  # A small circuit breaker bounds the latency: after `failure_threshold`
  # consecutive errors, Redis is skipped for `open_for` seconds, so a hung
  # Redis costs the first few requests a timeout, not every request one per
  # matched throttle (increment then write, each up to the client timeout).
  #
  # `primary` must RAISE on a Redis error; build it with
  # Security::ResilientThrottleStore.redis_primary, whose error handler
  # re-raises.
  class ResilientThrottleStore
    REDIS_ERRORS = [ ::Redis::BaseError, ::RedisClient::Error, IOError, SystemCallError ].freeze

    attr_reader :primary, :fallback

    def self.redis_primary(url:, timeout: 1)
      ActiveSupport::Cache::RedisCacheStore.new(
        url: url,
        namespace: "rack_attack",
        connect_timeout: timeout,
        read_timeout: timeout,
        write_timeout: timeout,
        reconnect_attempts: 0,
        error_handler: ->(exception:, **) { raise exception }
      )
    end

    def initialize(primary:, fallback: ActiveSupport::Cache::MemoryStore.new(size: 16.megabytes),
                   failure_threshold: 3, open_for: 30)
      @primary = primary
      @fallback = fallback
      @failure_threshold = failure_threshold
      @open_for = open_for
      @failures = 0
      @open_until = nil
      @mutex = Mutex.new
    end

    def increment(name, amount = 1, **options)
      with_fallback(:increment, name, amount, **options)
    end

    def read(name, **options)
      with_fallback(:read, name, **options)
    end

    def write(name, value, **options)
      with_fallback(:write, name, value, **options)
    end

    def delete(name, **options)
      with_fallback(:delete, name, **options)
    end

    def delete_matched(matcher, **options)
      @fallback.delete_matched(matcher, **options)
      @primary.delete_matched(matcher, **options) if @primary.respond_to?(:delete_matched) && !open?
    rescue *REDIS_ERRORS => e
      record_failure(e)
    end

    def open?
      @mutex.synchronize { !@open_until.nil? && Time.current < @open_until }
    end

    private

    def with_fallback(method, *args, **options)
      return @fallback.public_send(method, *args, **options) if open?

      result = @primary.public_send(method, *args, **options)
      record_success
      result
    rescue *REDIS_ERRORS => e
      record_failure(e)
      @fallback.public_send(method, *args, **options)
    end

    def record_success
      @mutex.synchronize do
        @failures = 0
        @open_until = nil
      end
    end

    def record_failure(error)
      opened = @mutex.synchronize do
        @failures += 1
        next false if @failures < @failure_threshold

        @open_until = Time.current + @open_for
        true
      end
      return unless opened

      Rails.logger.warn(
        "[ResilientThrottleStore] Redis failing (#{error.class}); counting throttles in process " \
        "memory for #{@open_for}s"
      )
    end
  end
end

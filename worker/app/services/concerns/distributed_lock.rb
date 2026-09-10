# frozen_string_literal: true

# Distributed Lock pattern implementation for preventing concurrent job execution
# Uses Redis SET NX (set if not exists) with expiration for lock acquisition
module DistributedLock
  extend ActiveSupport::Concern

  class LockNotAcquiredError < StandardError; end
  class LockError < StandardError; end

  # Token-checked delete. Hoisted to a constant so the script is identical on
  # every release (and so a spec can assert against the same text).
  RELEASE_SCRIPT = <<~LUA
    if redis.call("get", KEYS[1]) == ARGV[1] then
      return redis.call("del", KEYS[1])
    else
      return 0
    end
  LUA

  included do
    attr_reader :lock_key, :lock_token
  end

  # Acquire a lock and execute the block
  # Returns nil if lock couldn't be acquired (unless raise_on_failure is true)
  #
  # @param key [String] The lock key (will be prefixed with "lock:")
  # @param ttl [Integer] Lock expiration in seconds (default: 300 = 5 minutes)
  # @param raise_on_failure [Boolean] Raise LockNotAcquiredError if lock can't be acquired
  # @param wait_timeout [Integer] How long to wait for lock acquisition (default: 0 = don't wait)
  # @param retry_interval [Float] Seconds between retry attempts when waiting (default: 0.5)
  # @yield The block to execute while holding the lock
  # @return The block's return value, or nil if lock wasn't acquired
  def with_lock(key, ttl: 300, raise_on_failure: false, wait_timeout: 0, retry_interval: 0.5)
    @lock_key = "lock:#{key}"
    @lock_token = generate_lock_token

    logger.debug "[DistributedLock] Attempting to acquire lock: #{@lock_key}"

    acquired = acquire_lock(ttl, wait_timeout, retry_interval)

    unless acquired
      message = "Failed to acquire lock: #{@lock_key}"
      logger.warn "[DistributedLock] #{message}"

      raise LockNotAcquiredError, message if raise_on_failure

      return nil
    end

    logger.info "[DistributedLock] Lock acquired: #{@lock_key} (TTL: #{ttl}s)"

    begin
      yield
    ensure
      release_lock
    end
  end

  # Check if a lock is currently held
  # @param key [String] The lock key
  # @return [Boolean]
  def lock_held?(key)
    full_key = "lock:#{key}"
    Sidekiq.redis { |conn| conn.exists(full_key) == 1 }
  rescue StandardError => e
    logger.error "[DistributedLock] Error checking lock status: #{e.message}"
    false
  end

  # Get remaining TTL for a lock
  # @param key [String] The lock key
  # @return [Integer, nil] Remaining seconds, or nil if lock doesn't exist
  def lock_ttl(key)
    full_key = "lock:#{key}"
    ttl = Sidekiq.redis { |conn| conn.ttl(full_key) }
    ttl.positive? ? ttl : nil
  rescue StandardError => e
    logger.error "[DistributedLock] Error getting lock TTL: #{e.message}"
    nil
  end

  private

  def acquire_lock(ttl, wait_timeout, retry_interval)
    deadline = Time.current + wait_timeout

    loop do
      # Try to acquire lock using SET NX EX (atomic set-if-not-exists with expiration)
      acquired = Sidekiq.redis do |conn|
        conn.set(@lock_key, @lock_token, nx: true, ex: ttl)
      end

      return true if acquired

      # If not waiting or past deadline, return failure
      return false if wait_timeout.zero? || Time.current >= deadline

      # Wait and retry
      sleep(retry_interval)
    end
  rescue StandardError => e
    logger.error "[DistributedLock] Error acquiring lock: #{e.message}"
    raise LockError, "Failed to acquire lock: #{e.message}"
  end

  # Only release if we still own the lock: compare the token, then delete,
  # atomically. A plain DEL would let a holder whose TTL expired mid-run delete
  # a lock a DIFFERENT process has since taken, releasing someone else's lock
  # and re-admitting the overlap the lock exists to prevent.
  #
  # THE CALL FORM IS LOAD-BEARING, and this is a fixed bug rather than a style
  # preference. This previously read:
  #
  #     conn.eval(lua_script, keys: [@lock_key], argv: [@lock_token])
  #
  # which is redis-rb's signature. Sidekiq 8 hands out a
  # `Sidekiq::RedisClientAdapter::CompatClient`, where that raises
  # `TypeError: Unsupported command argument type: Array` — and the rescue
  # below swallowed it, so the failure was invisible and THE LOCK WAS NEVER
  # RELEASED. It expired by TTL alone, which on a short-period cron silently
  # skipped most ticks while every run reported success.
  #
  # Measured on the live client, not inferred: with the old form the key was
  # still present after a clean run; with `call("EVAL", script, numkeys, ...)`
  # the owner's release returns 1 and the key is gone, and a non-owner's
  # returns 0 and the key stays.
  def release_lock
    result = Sidekiq.redis do |conn|
      conn.call("EVAL", RELEASE_SCRIPT, 1, @lock_key, @lock_token)
    end

    if result == 1
      logger.info "[DistributedLock] Lock released: #{@lock_key}"
    else
      logger.warn "[DistributedLock] Lock was already released or expired: #{@lock_key}"
    end
  rescue StandardError => e
    logger.error "[DistributedLock] Error releasing lock: #{e.message}"
  end

  def generate_lock_token
    # Unique token combining worker identity and random component
    "#{Process.pid}-#{Thread.current.object_id}-#{SecureRandom.hex(8)}"
  end

  def logger
    @logger ||= PowernodeWorker.application.logger
  end
end

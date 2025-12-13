# frozen_string_literal: true

# Distributed Lock pattern implementation for preventing concurrent job execution
# Uses Redis SET NX (set if not exists) with expiration for lock acquisition
module DistributedLock
  extend ActiveSupport::Concern

  class LockNotAcquiredError < StandardError; end
  class LockError < StandardError; end

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
    Sidekiq.redis { |conn| conn.exists?(full_key) }
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

  def release_lock
    # Only release if we still own the lock (compare token)
    # Use Lua script for atomic check-and-delete
    lua_script = <<-LUA
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end
    LUA

    result = Sidekiq.redis do |conn|
      conn.eval(lua_script, keys: [@lock_key], argv: [@lock_token])
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

# frozen_string_literal: true

# Clears rate-limit counters before every example.
#
# WHY. Controllers that rate-limit do so through the RateLimiting concern,
# which counts in Rails.cache under "rate_limit:<controller>:<ip>" — every
# example in a run shares one controller name and one remote IP (127.0.0.1),
# so they share one counter. Nothing reset it. Api::V1::Auth::PasswordsController
# overrides should_rate_limit? to `true # Always` with 3 attempts per 15
# MINUTES, a window longer than a suite takes, so the fourth password request
# in a run returns HTTP 429 regardless of what the example asserts.
#
# It presents as a cross-machine phantom rather than an ordering bug: five
# passwords_spec failures on one box and zero on another, from identical code
# and an identical suite. The cause is RateLimiting#check_and_increment_rate_limit's
# `return if ENV["DISABLE_RATE_LIMITING"] == "true"` — a developer box has a
# gitignored .env setting it, a freshly-provisioned box has no .env at all. The
# limiter is therefore silently inert exactly where anyone would look for it,
# and live everywhere else.
#
# Resetting the counter is preferable to setting that variable in test: the
# limiter stays exercised, its own specs keep working, and specs become
# order-independent because each starts from a known-empty counter rather than
# from whatever the previous examples happened to leave behind.
#
# Two stores are cleared because there are two independent limiters, and only
# the first is in this call path:
#   - Rails.cache        — the RateLimiting concern (what actually 429s here)
#   - Redis rate_limit:* — Security::RateLimiter, used by other endpoints
#
# The Redis pass is scoped with SCAN + DEL rather than FLUSHDB on purpose: on a
# developer box the test environment resolves to the SAME Redis logical database
# as the running platform (no REDIS_URL/REDIS_DB set), so a flush would wipe
# live sessions, caches and queues.
RSpec.configure do |config|
  config.before(:each) do
    # 1. Rails.cache — the RateLimiting concern's counter.
    begin
      Rails.cache.delete_matched("rate_limit:*")
    rescue NotImplementedError, StandardError
      # Not every store implements delete_matched; fall back to a full clear,
      # which is safe here because the test store is per-process (MemoryStore)
      # and shares nothing with a running platform.
      begin
        Rails.cache.clear
      rescue StandardError
        nil
      end
    end

    # 2. Redis — Security::RateLimiter's counter, for endpoints that use it.
    next unless defined?(::Powernode::Redis)

    begin
      redis = ::Powernode::Redis.client
      cursor = "0"
      loop do
        cursor, keys = redis.scan(cursor, match: "rate_limit:*", count: 500)
        redis.del(*keys) unless keys.empty?
        break if cursor == "0"
      end
    rescue StandardError
      # Redis being unavailable must never fail an example that does not use it.
      nil
    end
  end
end

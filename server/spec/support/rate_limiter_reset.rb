# frozen_string_literal: true

# Clears Security::RateLimiter counters before every example.
#
# WHY THIS IS NEEDED. The limiter is backed by Redis, not Rails.cache, so its
# counters outlive both the example and the entire run. Nothing reset them, and
# several endpoints rate-limit unconditionally — Api::V1::Auth::PasswordsController
# declares `should_rate_limit? => true # Always` with 3 attempts per IP per 15
# MINUTES, a window far longer than a suite takes. So the fourth password
# request in a run gets HTTP 429 regardless of what the example asserts.
#
# The result was a cross-machine phantom: five passwords_spec failures on one
# box and zero on another, from identical code, identical suite, identical
# example count. They pass in isolation and fail in file order, which reads as
# an environment difference and is not one. Two full suite runs were spent
# chasing it.
#
# SCOPED DELETION, NOT FLUSHDB — deliberately. On a developer box the test
# environment resolves to the SAME Redis logical database as the running
# platform (no REDIS_URL/REDIS_DB is set, and the AdminSetting lookup falls back
# to redis://localhost:6379/0). A flush here would wipe live platform state:
# sessions, caches, queues. Deleting only the limiter's own `rate_limit:*`
# namespace touches nothing else, and uses SCAN rather than KEYS so it never
# blocks the server.
#
# That shared-database arrangement is itself worth fixing — the suite should not
# share Redis with a running platform at all — but that is a broader change than
# making these specs deterministic, and this hook is correct either way.
RSpec.configure do |config|
  config.before(:each) do
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
      # The specs that DO depend on the limiter will fail on their own terms,
      # which is a clearer signal than a connection error in a before hook.
      nil
    end
  end
end

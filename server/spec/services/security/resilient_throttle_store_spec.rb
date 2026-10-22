# frozen_string_literal: true

require "rails_helper"

# Rack::Attack's Redis store must not fail open. A RedisCacheStore answers nil
# on a Redis error; Rack::Attack's do_count then writes 1 and reports 1, so
# every throttle (login, 2FA, password reset, node claim/enroll) stopped
# counting while Redis was down. ResilientThrottleStore counts in a
# per-process MemoryStore instead, and a short circuit breaker stops each
# request paying a Redis timeout once Redis is known to be failing.
RSpec.describe Security::ResilientThrottleStore do
  # Stands in for a RedisCacheStore whose Redis is down: every call raises
  # (the store's error handler re-raises) after an optional delay.
  let(:failing_primary) do
    Class.new do
      attr_reader :calls

      def initialize(delay: 0)
        @delay = delay
        @calls = 0
      end

      %i[increment read write delete].each do |name|
        define_method(name) do |*_args, **_kwargs|
          @calls += 1
          sleep @delay if @delay.positive?
          raise ::Redis::CannotConnectError, "redis down"
        end
      end
    end
  end

  def cache_with(store)
    Rack::Attack::Cache.new(store: store)
  end

  it "keeps counting in process memory while Redis errors" do
    store = described_class.new(primary: failing_primary.new)
    cache = cache_with(store)

    counts = Array.new(6) { cache.count("auth_login_by_ip:203.0.113.9", 3600) }

    expect(counts).to eq([ 1, 2, 3, 4, 5, 6 ])
  end

  it "uses Redis while it is healthy" do
    primary = ActiveSupport::Cache::MemoryStore.new
    store = described_class.new(primary: primary)

    cache_with(store).count("k", 60)
    cache_with(store).count("k", 60)

    expect(primary.instance_variable_get(:@data).size).to eq(1)
  end

  it "stops calling Redis once the breaker opens, so requests do not keep paying its timeout" do
    primary = failing_primary.new(delay: 0.05)
    store = described_class.new(primary: primary, failure_threshold: 2, open_for: 30)
    cache = cache_with(store)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    20.times { cache.count("k", 60) }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    expect(primary.calls).to eq(2)
    expect(elapsed).to be < 0.5
  end

  it "tries Redis again once the breaker's window has passed" do
    primary = failing_primary.new
    store = described_class.new(primary: primary, failure_threshold: 1, open_for: 30)
    store.increment("k", 1, expires_in: 60)

    travel(31.seconds) { store.increment("k", 1, expires_in: 60) }

    expect(primary.calls).to eq(2)
  end

  describe "with Rack::Attack" do
    let(:app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

    around do |example|
      original_store = Rack::Attack.cache.store
      original_enabled = Rack::Attack.enabled
      Rack::Attack.enabled = true
      Rack::Attack.cache.store = described_class.new(primary: failing_primary.new)
      example.run
    ensure
      Rack::Attack.cache.store = original_store
      Rack::Attack.enabled = original_enabled
    end

    before { allow(Rack::Attack).to receive(:rate_limiting_enabled?).and_return(true) }

    # two_factor_reauth_by_ip (5 per 5 minutes) is registered in the test env;
    # the login rules sit behind the initializer's test-env guard but count
    # through the same store.
    it "still trips a throttle while Redis is down" do
      env = lambda do
        Rack::MockRequest.env_for("/api/v1/two_factor/disable", method: "DELETE", "REMOTE_ADDR" => "203.0.113.10")
      end
      statuses = Array.new(6) { Rack::Attack.new(app).call(env.call).first }

      expect(statuses.first(5)).to all(eq(200))
      expect(statuses.last).to eq(429)
    end
  end
end

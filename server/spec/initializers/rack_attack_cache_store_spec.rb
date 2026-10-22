# frozen_string_literal: true

require "rails_helper"

# Rack::Attack counts every throttle on every request. On Rails.cache that
# is fine for MemoryStore and Redis, but under solid_cache each count is a
# row-locked upsert in Postgres on the request path. When Redis is
# configured, Rack::Attack gets its own RedisCacheStore on that Redis;
# without Redis it falls back to Rails.cache.
RSpec.describe "Rack::Attack cache store" do
  it "uses a RedisCacheStore on the configured Redis when REDIS_URL is set" do
    allow(ActiveSupport::Cache::RedisCacheStore).to receive(:new).and_call_original

    store = Rack::Attack.cache_store_for(redis_url: "redis://redis.example.test:6379/0")

    expect(store).to be_a(Security::ResilientThrottleStore)
    expect(store.primary).to be_a(ActiveSupport::Cache::RedisCacheStore)
    expect(ActiveSupport::Cache::RedisCacheStore).to have_received(:new)
      .with(hash_including(url: "redis://redis.example.test:6379/0", namespace: "rack_attack"))
  end

  it "falls back to Rails.cache when no Redis is configured" do
    expect(Rack::Attack.cache_store_for(redis_url: nil)).to be(Rails.cache)
    expect(Rack::Attack.cache_store_for(redis_url: "")).to be(Rails.cache)
  end

  it "raises nothing into the request on a Redis error" do
    store = Rack::Attack.cache_store_for(redis_url: "redis://127.0.0.1:1/0")

    expect { store.increment("rack_attack:spec", 1, expires_in: 60) }.not_to raise_error
  end

  # A RedisCacheStore answers nil on a Redis error and Rack::Attack then
  # reports a count of 1 for every request, so no throttle could ever trip
  # while Redis was down. The configured store must keep counting.
  it "keeps counting, so throttles still trip, when Redis is unreachable" do
    cache = Rack::Attack::Cache.new(store: Rack::Attack.cache_store_for(redis_url: "redis://127.0.0.1:1/0"))

    counts = Array.new(3) { cache.count("auth_login_by_ip:203.0.113.11", 3600) }

    expect(counts).to eq([ 1, 2, 3 ])
  end

  it "resolves the configured Redis from REDIS_URL through Powernode::Redis" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("REDIS_URL").and_return("redis://configured.example.test:6379/0")
    allow(Powernode::Redis).to receive(:url).and_return("redis://resolved.example.test:6379/0")

    expect(Rack::Attack.configured_redis_url).to eq("redis://resolved.example.test:6379/0")

    allow(ENV).to receive(:[]).with("REDIS_URL").and_return(nil)
    expect(Rack::Attack.configured_redis_url).to be_nil
  end
end

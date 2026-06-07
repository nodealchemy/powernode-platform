# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::ResponseCacheService, type: :service do
  # Minimal in-memory, thread-safe Redis stand-in supporting exactly the
  # commands ResponseCacheService uses (get/setex/set-nx-px/del/scan/incr/
  # expire/ttl). Real Redis is intentionally not required so these specs are
  # hermetic; the stateful behaviour (SETNX lock, TTL, prefix SCAN) is what the
  # singleflight + invalidate paths exercise.
  class FakeRedis
    def initialize
      @data = {}
      @expires_at = {}
      @mutex = Mutex.new
    end

    def get(key)
      @mutex.synchronize { live?(key) ? @data[key] : nil }
    end

    def setex(key, ttl, value)
      @mutex.synchronize do
        @data[key] = value
        @expires_at[key] = monotonic + ttl.to_i
      end
      "OK"
    end

    # Supports SET k v NX PX <ms> (the recompute lock) and plain SET.
    def set(key, value, nx: false, px: nil, ex: nil)
      @mutex.synchronize do
        return nil if nx && live?(key)

        @data[key] = value
        if px
          @expires_at[key] = monotonic + (px.to_f / 1000.0)
        elsif ex
          @expires_at[key] = monotonic + ex.to_i
        end
        "OK"
      end
    end

    def del(*keys)
      @mutex.synchronize do
        keys.flatten.count do |k|
          existed = @data.key?(k)
          @data.delete(k)
          @expires_at.delete(k)
          existed
        end
      end
    end

    def incr(key)
      @mutex.synchronize do
        @data[key] = (live?(key) ? @data[key].to_i : 0) + 1
        @data[key]
      end
    end

    def expire(key, ttl)
      @mutex.synchronize do
        next 0 unless @data.key?(key)

        @expires_at[key] = monotonic + ttl.to_i
        1
      end
    end

    def ttl(key)
      @mutex.synchronize do
        next -2 unless @data.key?(key)
        next -1 unless @expires_at.key?(key)

        remaining = (@expires_at[key] - monotonic).to_i
        remaining.positive? ? remaining : -2
      end
    end

    # Single-pass SCAN emulation: returns ["0", matching_keys].
    def scan(_cursor, match:, count: 1000)
      @mutex.synchronize do
        regex = Regexp.new("\\A#{Regexp.escape(match).gsub('\*', '.*')}\\z")
        matched = @data.keys.select { |k| live?(k) && k.match?(regex) }
        ["0", matched]
      end
    end

    private

    def live?(key)
      return false unless @data.key?(key)
      return true unless @expires_at.key?(key)

      if @expires_at[key] <= monotonic
        @data.delete(key)
        @expires_at.delete(key)
        false
      else
        true
      end
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  let(:fake_redis) { FakeRedis.new }
  let(:data_source) { create(:ai_data_source) }
  let(:endpoint) { create(:ai_data_source_endpoint, data_source: data_source, cache_ttl_seconds: 120) }

  before do
    allow(Powernode::Redis).to receive(:client).and_return(fake_redis)
    # Isolate the cache under test from the unrelated data-source -> knowledge-graph
    # sync: creating a source fires an after_commit that would otherwise reach Redis
    # via the embedding service and pollute the cache-interaction assertions.
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    # Cache enabled for the source (feature flag on).
    allow(Shared::FeatureFlagService).to receive(:enabled?).and_return(true)
    described_class.reset_metrics!
  end

  describe ".fetch" do
    it "requires a block" do
      expect do
        described_class.fetch(data_source: data_source, endpoint: endpoint)
      end.to raise_error(ArgumentError, /block required/)
    end

    it "computes and caches on a miss, then serves from cache on the next call (hit)" do
      calls = 0
      payload = { "records" => [{ "city" => "NYC" }] }

      first = described_class.fetch(data_source: data_source, endpoint: endpoint) do
        calls += 1
        payload
      end
      expect(first).to eq(payload)
      expect(calls).to eq(1)

      second = described_class.fetch(data_source: data_source, endpoint: endpoint) do
        calls += 1
        { "should" => "not be used" }
      end

      expect(second).to eq(payload)
      expect(calls).to eq(1) # block not re-invoked on hit
    end

    it "records a miss then a hit in metrics" do
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } }
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } }

      metrics = described_class.metrics
      expect(metrics[:misses]).to eq(1)
      expect(metrics[:hits]).to eq(1)
    end

    it "keys by params so different params miss independently" do
      described_class.fetch(data_source: data_source, endpoint: endpoint, params: { "q" => "a" }) { { "v" => "a" } }
      result_b = described_class.fetch(data_source: data_source, endpoint: endpoint, params: { "q" => "b" }) { { "v" => "b" } }

      expect(result_b).to eq({ "v" => "b" })
      expect(described_class.metrics[:misses]).to eq(2)
    end

    it "treats params as equal regardless of key ordering / symbol-vs-string" do
      first = described_class.fetch(
        data_source: data_source, endpoint: endpoint, params: { "a" => 1, "b" => 2 }
      ) { { "v" => "first" } }

      second = described_class.fetch(
        data_source: data_source, endpoint: endpoint, params: { b: 2, a: 1 }
      ) { { "v" => "second" } }

      expect(first).to eq({ "v" => "first" })
      expect(second).to eq({ "v" => "first" }) # collapsed to the same key
    end

    it "bypasses the cache entirely when disabled for the source" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).and_return(false)
      expect(fake_redis).not_to receive(:setex)

      calls = 0
      2.times do
        described_class.fetch(data_source: data_source, endpoint: endpoint) do
          calls += 1
          { "x" => 1 }
        end
      end

      expect(calls).to eq(2) # recomputed every time
    end

    it "falls back to direct compute if the cache layer raises" do
      allow(fake_redis).to receive(:get).and_raise(Redis::ConnectionError, "down")

      result = described_class.fetch(data_source: data_source, endpoint: endpoint) { { "ok" => true } }
      expect(result).to eq({ "ok" => true })
    end
  end

  describe "TTL derived from the endpoint" do
    it "writes the cache entry with the endpoint's cache_ttl_seconds" do
      captured_ttl = nil
      allow(fake_redis).to receive(:setex).and_wrap_original do |orig, key, ttl, value|
        captured_ttl = ttl
        orig.call(key, ttl, value)
      end

      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } }

      expect(captured_ttl).to eq(120) # endpoint.cache_ttl_seconds
    end

    it "uses DEFAULT_TTL when the endpoint declares no cache_ttl_seconds" do
      endpoint.update!(cache_ttl_seconds: nil)
      captured_ttl = nil
      allow(fake_redis).to receive(:setex).and_wrap_original do |orig, key, ttl, value|
        captured_ttl = ttl
        orig.call(key, ttl, value)
      end

      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } }

      expect(captured_ttl).to eq(described_class::DEFAULT_TTL.to_i) # 300
    end
  end

  describe ".invalidate" do
    it "deletes all param-variants for a data_source + endpoint" do
      described_class.fetch(data_source: data_source, endpoint: endpoint, params: { "q" => "a" }) { { "v" => "a" } }
      described_class.fetch(data_source: data_source, endpoint: endpoint, params: { "q" => "b" }) { { "v" => "b" } }

      deleted = described_class.invalidate(data_source: data_source, endpoint: endpoint)
      expect(deleted).to eq(2)

      # Next fetch is a fresh miss (block runs again).
      calls = 0
      described_class.fetch(data_source: data_source, endpoint: endpoint, params: { "q" => "a" }) do
        calls += 1
        { "v" => "a2" }
      end
      expect(calls).to eq(1)
    end

    it "deletes every endpoint variant when scoped to the data_source only" do
      other_endpoint = create(:ai_data_source_endpoint, data_source: data_source)
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "v" => 1 } }
      described_class.fetch(data_source: data_source, endpoint: other_endpoint) { { "v" => 2 } }

      deleted = described_class.invalidate(data_source: data_source)
      expect(deleted).to eq(2)
    end

    it "returns 0 when there is nothing to invalidate" do
      expect(described_class.invalidate(data_source: data_source, endpoint: endpoint)).to eq(0)
    end
  end

  describe ".write / .read" do
    it "round-trips an explicitly written payload" do
      payload = { "records" => [{ "temp" => "72" }] }
      expect(
        described_class.write(data_source: data_source, endpoint: endpoint, payload: payload, ttl: 60)
      ).to be(true)

      expect(described_class.read(data_source: data_source, endpoint: endpoint)).to eq(payload)
    end

    it "read returns nil and counts a miss when absent" do
      expect(described_class.read(data_source: data_source, endpoint: endpoint)).to be_nil
      expect(described_class.metrics[:misses]).to eq(1)
    end
  end

  describe ".metrics" do
    it "reports hits, misses, total and hit_rate" do
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } } # miss
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } } # hit
      described_class.fetch(data_source: data_source, endpoint: endpoint) { { "a" => 1 } } # hit

      metrics = described_class.metrics
      expect(metrics[:hits]).to eq(2)
      expect(metrics[:misses]).to eq(1)
      expect(metrics[:total]).to eq(3)
      expect(metrics[:hit_rate]).to eq(66.7)
    end

    it "returns zeroed metrics with a 0 hit_rate when empty" do
      expect(described_class.metrics).to include(hits: 0, misses: 0, total: 0, hit_rate: 0)
    end
  end

  describe "singleflight (cache stampede protection)" do
    it "invokes the recompute block exactly once when many callers race on a cold key" do
      invocations = 0
      invocation_mutex = Mutex.new
      barrier = Queue.new
      payload = { "records" => [{ "city" => "NYC" }] }

      compute = lambda do
        invocation_mutex.synchronize { invocations += 1 }
        # Hold the lock long enough that the other threads land in
        # wait_for_value and observe the value the holder publishes.
        barrier.pop # released by the test once all threads have started
        sleep 0.2
        payload
      end

      threads = 5.times.map do
        Thread.new do
          described_class.fetch(data_source: data_source, endpoint: endpoint, &compute)
        end
      end

      # Let every thread reach the lock contention point, then unblock the holder.
      sleep 0.1
      5.times { barrier << :go }

      results = threads.map(&:value)

      expect(invocations).to eq(1)
      expect(results).to all(eq(payload))
    end
  end

  describe "constants" do
    it "exposes DEFAULT_TTL of 5 minutes" do
      expect(described_class::DEFAULT_TTL).to eq(5.minutes)
    end

    it "namespaces cache keys under data_source_cache" do
      expect(described_class::REDIS_NAMESPACE).to eq("data_source_cache")
    end
  end
end

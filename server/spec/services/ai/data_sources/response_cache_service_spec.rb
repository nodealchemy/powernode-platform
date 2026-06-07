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

    # SADD — append member(s) to a Set stored at key (used by the tag index).
    def sadd(key, *members)
      @mutex.synchronize do
        set = (live?(key) ? @data[key] : nil)
        set = Set.new unless set.is_a?(Set)
        before = set.size
        members.flatten.each { |m| set.add(m) }
        @data[key] = set
        set.size - before
      end
    end

    # SMEMBERS — return the Set's members as an Array (empty when absent).
    def smembers(key)
      @mutex.synchronize { live?(key) && @data[key].is_a?(Set) ? @data[key].to_a : [] }
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

  # ==========================================================================
  # Surrogate-key (tag) invalidation. .write indexes each entry's cache key into
  # a Redis SET per tag ("data_source_cache:tag:<tag>"); .invalidate_by_tag drops
  # every key in the set then the set itself. .write stays backward compatible
  # (tags optional) and tags by default_tags when no tags are supplied.
  # ==========================================================================
  describe "tag / surrogate-key cache invalidation" do
    describe ".default_tags" do
      it "addresses an entry by data source id, endpoint id, and endpoint slug" do
        expect(described_class.default_tags(data_source, endpoint)).to eq(
          ["ds:#{data_source.id}", "endpoint:#{endpoint.id}", "slug:#{endpoint.slug}"]
        )
      end

      it "omits endpoint tags when no endpoint is given (source-granularity entries)" do
        expect(described_class.default_tags(data_source, nil)).to eq(["ds:#{data_source.id}"])
      end
    end

    describe ".write default tagging" do
      it "indexes the entry under each default tag set so it is tag-addressable" do
        described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 1 })

        cache_key = described_class.send(:build_cache_key, data_source, endpoint, {})
        described_class.default_tags(data_source, endpoint).each do |tag|
          expect(fake_redis.smembers("#{described_class::TAG_NAMESPACE}:#{tag}")).to include(cache_key)
        end
      end

      it "uses explicit tags when supplied instead of the defaults" do
        described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 1 }, tags: ["team:weather"])

        cache_key = described_class.send(:build_cache_key, data_source, endpoint, {})
        expect(fake_redis.smembers("#{described_class::TAG_NAMESPACE}:team:weather")).to include(cache_key)
        # The defaults are NOT applied when explicit tags are given.
        expect(fake_redis.smembers("#{described_class::TAG_NAMESPACE}:ds:#{data_source.id}")).to be_empty
      end

      it "still writes (and round-trips) the payload, returning true" do
        expect(
          described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 1 })
        ).to be(true)
        expect(described_class.read(data_source: data_source, endpoint: endpoint)).to eq({ "v" => 1 })
      end
    end

    describe ".invalidate_by_tag" do
      it "drops every cache entry recorded under the tag and returns the count" do
        # Two distinct param-variants, both tagged with the shared endpoint slug.
        described_class.write(data_source: data_source, endpoint: endpoint, params: { "q" => "a" }, payload: { "v" => "a" })
        described_class.write(data_source: data_source, endpoint: endpoint, params: { "q" => "b" }, payload: { "v" => "b" })

        count = described_class.invalidate_by_tag("slug:#{endpoint.slug}")
        expect(count).to eq(2)

        # Both variants are gone.
        expect(described_class.read(data_source: data_source, endpoint: endpoint, params: { "q" => "a" })).to be_nil
        expect(described_class.read(data_source: data_source, endpoint: endpoint, params: { "q" => "b" })).to be_nil
      end

      it "deletes the tag index set itself after invalidation" do
        described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 1 })
        tag = "ds:#{data_source.id}"

        described_class.invalidate_by_tag(tag)
        expect(fake_redis.smembers("#{described_class::TAG_NAMESPACE}:#{tag}")).to be_empty
      end

      it "returns 0 for a blank or unknown tag" do
        expect(described_class.invalidate_by_tag("")).to eq(0)
        expect(described_class.invalidate_by_tag(nil)).to eq(0)
        expect(described_class.invalidate_by_tag("nope:does-not-exist")).to eq(0)
      end

      it "fails open (logs, returns 0) when the tag index read raises" do
        allow(fake_redis).to receive(:smembers).and_raise(Redis::ConnectionError, "down")
        expect(Rails.logger).to receive(:error).with(/invalidate_by_tag failed/)

        expect(described_class.invalidate_by_tag("ds:#{data_source.id}")).to eq(0)
      end

      it "isolates a tag from sibling tags (only the named tag is cleared)" do
        described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 1 }, tags: ["keep:me"])
        other = create(:ai_data_source_endpoint, data_source: data_source)
        described_class.write(data_source: data_source, endpoint: other, payload: { "v" => 2 }, tags: ["drop:me"])

        expect(described_class.invalidate_by_tag("drop:me")).to eq(1)
        # The untouched tag's entry is still readable.
        expect(described_class.read(data_source: data_source, endpoint: endpoint)).to eq({ "v" => 1 })
      end
    end

    it "does not break .write when the Redis SET commands are unsupported (fail-open index)" do
      # Simulate a Redis without SADD: the tag index step must be swallowed while
      # the payload write itself still succeeds.
      allow(fake_redis).to receive(:sadd).and_raise(NoMethodError, "undefined method sadd")

      expect(
        described_class.write(data_source: data_source, endpoint: endpoint, payload: { "v" => 9 })
      ).to be(true)
      expect(described_class.read(data_source: data_source, endpoint: endpoint)).to eq({ "v" => 9 })
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

  # ==========================================================================
  # Phase 3 — stale-while-revalidate (SWR) / stale-if-error grace window
  #
  # write/fetch keep the Redis key alive past its HARD expiry by
  # grace_window = max(stale_while_revalidate_seconds, stale_if_error_seconds)
  # while preserving the hard-expiry epoch ("e"). read_stale exposes that as a
  # flagged descriptor; fetch serves a hard-expired-but-in-grace entry (flagged)
  # and kicks off a single background refresh. With BOTH stale_* columns nil the
  # grace window is 0 and the legacy behaviour is byte-for-byte preserved.
  # ==========================================================================
  describe "stale-while-revalidate" do
    # The single cached key currently live in the fake (there is exactly one
    # data_source_cache entry per param-variant). Returns [key, parsed_envelope].
    def stored_cache_entry
      # Match a payload entry, NOT the metrics/lock keys that share the namespace
      # prefix (data_source_cache:metrics / :lock) — those hold integers, not JSON.
      key = fake_redis.instance_variable_get(:@data).keys
                      .find { |k| k.start_with?("#{described_class::REDIS_NAMESPACE}:") &&
                                  !k.start_with?("#{described_class::METRICS_NAMESPACE}:") &&
                                  !k.start_with?("#{described_class::LOCK_NAMESPACE}:") }
      return [nil, nil] unless key

      [key, JSON.parse(fake_redis.get(key))]
    end

    # Rewrite the stored entry's HARD-expiry epoch ("e") to `seconds_ago` in the
    # past (delta forced to 0 so the XFetch early-refresh roll never fires),
    # leaving the Redis key itself live — i.e. exactly the state of an entry that
    # has passed its hard TTL but is still inside the grace window.
    def expire_hard!(seconds_ago:)
      key, env = stored_cache_entry
      raise "no cached entry to expire" unless key

      env["e"] = ((Time.now.to_f - seconds_ago) * 1000).to_i
      env["d"] = 0.0
      fake_redis.set(key, env.to_json)
    end

    describe ".read_stale" do
      it "returns nil on a miss" do
        expect(
          described_class.read_stale(data_source: data_source, endpoint: endpoint)
        ).to be_nil
      end

      it "returns a fresh (not stale) descriptor while within the hard TTL" do
        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "v" => 1 }, ttl: 120
        )

        desc = described_class.read_stale(data_source: data_source, endpoint: endpoint)

        expect(desc[:payload]).to eq({ "v" => 1 })
        expect(desc[:stale]).to be(false)
        expect(desc[:hard_expired]).to be(false)
        expect(desc[:age_seconds]).to be >= 0
        expect(desc[:stale_age_seconds]).to eq(0)
      end

      it "returns a stale/hard_expired descriptor with the elapsed-past-expiry age once past the hard TTL" do
        endpoint.update!(stale_if_error_seconds: 600) # keep the key alive past hard expiry
        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "v" => "lkg" }, ttl: 120
        )
        expire_hard!(seconds_ago: 90) # 90s past the hard expiry, still in the 600s grace window

        desc = described_class.read_stale(data_source: data_source, endpoint: endpoint)

        expect(desc[:payload]).to eq({ "v" => "lkg" })
        expect(desc[:stale]).to be(true)
        expect(desc[:hard_expired]).to be(true)
        # stale_age is measured from the moment the entry went stale (past hard expiry).
        expect(desc[:stale_age_seconds]).to be_within(2).of(90)
        expect(desc[:age_seconds]).to be >= desc[:stale_age_seconds]
      end

      it "does NOT move the hit/miss metrics (side-channel read)" do
        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "v" => 1 }, ttl: 120
        )

        described_class.read_stale(data_source: data_source, endpoint: endpoint)

        expect(described_class.metrics).to include(hits: 0, misses: 0)
      end
    end

    describe ".fetch with stale_while_revalidate_seconds set" do
      before { endpoint.update!(stale_while_revalidate_seconds: 600) }

      it "extends the Redis TTL by the grace window while keeping the hard-expiry epoch" do
        captured_ttl = nil
        allow(fake_redis).to receive(:setex).and_wrap_original do |orig, key, ttl, value|
          captured_ttl = ttl
          orig.call(key, ttl, value)
        end

        described_class.fetch(data_source: data_source, endpoint: endpoint) { { "v" => 1 } }

        # Redis key lives for hard TTL (120) + grace window (600).
        expect(captured_ttl).to eq(120 + 600)

        # ...but the stored HARD-expiry epoch is only ~hard-TTL out, so read_stale
        # still flips to stale at the hard boundary, not the extended one.
        _key, env = stored_cache_entry
        hard_ttl_remaining_ms = env["e"] - (Time.now.to_f * 1000).to_i
        expect(hard_ttl_remaining_ms).to be <= 120_000
        expect(hard_ttl_remaining_ms).to be > 0
      end

      it "serves a hard-expired-but-in-grace entry (flagged) and schedules ONE background refresh" do
        # Stub the detached refresh so the spec stays hermetic (no Thread/DB work).
        allow(described_class).to receive(:schedule_background_refresh)

        # Seed an entry, then push it past its hard expiry (still inside grace).
        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "stale" => "value" }, ttl: 120
        )
        expire_hard!(seconds_ago: 30)

        recompute_calls = 0
        served = described_class.fetch(data_source: data_source, endpoint: endpoint) do
          recompute_calls += 1
          { "fresh" => "value" }
        end

        # The stale value is served WITHOUT recomputing in the caller's path...
        expect(served).to eq({ "stale" => "value" })
        expect(recompute_calls).to eq(0)
        # ...and exactly one background refresh is kicked off to repopulate it.
        expect(described_class).to have_received(:schedule_background_refresh)
          .with(data_source, endpoint, {}).once
      end

      it "counts the stale serve as a hit (not a miss)" do
        allow(described_class).to receive(:schedule_background_refresh)
        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "stale" => "value" }, ttl: 120
        )
        expire_hard!(seconds_ago: 30)
        described_class.reset_metrics!

        described_class.fetch(data_source: data_source, endpoint: endpoint) { { "fresh" => 1 } }

        expect(described_class.metrics).to include(hits: 1, misses: 0)
      end
    end

    describe "schedule_background_refresh" do
      before { endpoint.update!(stale_while_revalidate_seconds: 600) }

      it "invokes MonitorService#refresh! for the served param-variant under an NX lock" do
        monitor = instance_double(Ai::DataSources::MonitorService)
        allow(Ai::DataSources::MonitorService).to receive(:new).and_return(monitor)
        # The detached refresh runs on a Thread; capture it so the spec can join.
        allow(monitor).to receive(:refresh!).and_return(true)
        captured_thread = nil
        allow(Thread).to receive(:new) do |&blk|
          captured_thread = Thread.start(&blk)
          captured_thread
        end

        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "stale" => "v" }, ttl: 120
        )
        expire_hard!(seconds_ago: 30)

        described_class.fetch(data_source: data_source, endpoint: endpoint) { { "fresh" => 1 } }
        captured_thread&.join(2)

        expect(monitor).to have_received(:refresh!)
          .with(data_source: data_source, endpoint: endpoint, params: {})
      end

      it "schedules only ONE background refresh per key while the NX lock is held" do
        monitor = instance_double(Ai::DataSources::MonitorService)
        allow(Ai::DataSources::MonitorService).to receive(:new).and_return(monitor)
        # Hold the refresh open so the NX refresh-lock stays taken across both serves.
        gate = Queue.new
        allow(monitor).to receive(:refresh!) { gate.pop; true }
        threads = []
        allow(Thread).to receive(:new) { |&blk| t = Thread.start(&blk); threads << t; t }

        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "stale" => "v" }, ttl: 120
        )
        expire_hard!(seconds_ago: 30)

        2.times do
          described_class.fetch(data_source: data_source, endpoint: endpoint) { { "fresh" => 1 } }
        end

        gate << :go # release the (single) refresher
        threads.each { |t| t.join(2) }

        # Two stale serves, but the NX refresh-lock collapses them to one refresh.
        expect(monitor).to have_received(:refresh!).once
      end
    end

    describe ".fetch with BOTH stale_* nil (legacy / OFF)" do
      # endpoint has cache_ttl_seconds 120 and neither stale_* column set.
      it "writes with a Redis TTL equal to the hard TTL (no grace window)" do
        captured_ttl = nil
        allow(fake_redis).to receive(:setex).and_wrap_original do |orig, key, ttl, value|
          captured_ttl = ttl
          orig.call(key, ttl, value)
        end

        described_class.fetch(data_source: data_source, endpoint: endpoint) { { "v" => 1 } }

        expect(captured_ttl).to eq(120) # hard TTL only — grace window is 0
      end

      it "treats a hard-expired entry as a miss and recomputes (never serves stale)" do
        expect(described_class).not_to receive(:schedule_background_refresh)

        described_class.write(
          data_source: data_source, endpoint: endpoint, payload: { "stale" => "value" }, ttl: 120
        )
        expire_hard!(seconds_ago: 30)

        recompute_calls = 0
        served = described_class.fetch(data_source: data_source, endpoint: endpoint) do
          recompute_calls += 1
          { "fresh" => "value" }
        end

        # SWR off -> the hard-expired entry is NOT served; the block recomputes.
        expect(served).to eq({ "fresh" => "value" })
        expect(recompute_calls).to eq(1)
      end
    end
  end
end

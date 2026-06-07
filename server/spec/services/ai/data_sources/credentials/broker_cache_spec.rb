# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::BrokerCache — Redis-backed cache for SHORT-LIVED
# brokered credential material, with clock-skew trimming and a SETNX singleflight
# so a swarm hitting lease expiry does not hammer the upstream authority
# (AssumeRole / the OAuth token_url / the Vault dynamic engine).
#
# HERMETIC NOTE: this spec uses the REAL shared Redis client
# (Powernode::Redis.client, available in test) for the cache itself — exactly as
# robots_service_spec.rb does — because the cache READ path and the singleflight
# lock are Redis-command behaviours we want to exercise for real, not against a
# fake. NO network, AWS, Vault, or OAuth endpoint is ever touched: the only thing
# .fetch does on a miss is call the supplied block, and every block here is a
# pure in-process lambda (no broker, no HTTP). Each example scrubs the
# "ds_cred_broker:" namespace in an after hook so cached material / locks never
# leak between examples, and uses a UNIQUE cache key so parallel reruns stay
# isolated.
#
# The PRIORITY regression pinned here (see "block raising") is the major review
# fix: the compute happens EXACTLY ONCE, OUTSIDE any rescue, so a raising block
# propagates and is never silently retried (the old code re-ran it on the rescue
# path, double-calling the upstream and defeating singleflight).
RSpec.describe Ai::DataSources::Credentials::BrokerCache, type: :service do
  # A fresh, isolated key per example. The namespace flush below is
  # belt-and-suspenders on top of this.
  let(:cache_key) { "spec-#{SecureRandom.hex(8)}" }

  # The Redis key the impl actually writes under (NAMESPACE + caller key).
  let(:full_key) { "#{described_class::NAMESPACE}#{cache_key}" }

  # A simple, JSON-round-trippable material Hash. The cache stores it as JSON and
  # parses it back with STRING keys on a hit, so all assertions compare against
  # the string-keyed form.
  let(:material) { { "access_key_id" => "AKIA_TEST", "secret_access_key" => "shhh" } }
  let(:material_string_keys) { { "access_key_id" => "AKIA_TEST", "secret_access_key" => "shhh" } }

  # Scrub every brokered-credential cache + lock key so nothing leaks across
  # examples (real shared Redis). Mirrors robots_service_spec.rb's flush.
  def flush_broker_cache!
    client = Powernode::Redis.client
    return unless client

    keys = client.keys("#{described_class::NAMESPACE}*")
    client.del(*keys) if keys.any?
  rescue StandardError
    nil
  end

  after { flush_broker_cache! }

  # ==========================================================================
  # .ttl_with_skew — derive cache lease seconds from an absolute expiry
  # ==========================================================================
  describe ".ttl_with_skew" do
    it "returns the positive remaining seconds (minus skew) for a future expiry" do
      ttl = described_class.ttl_with_skew(expires_at: Time.current + 300, skew_seconds: 30)

      # 300 remaining - 30 skew = ~270; allow a hair of clock movement during the call.
      expect(ttl).to be_between(268, 270).inclusive
    end

    it "returns the full remaining seconds when no skew is supplied" do
      ttl = described_class.ttl_with_skew(expires_at: Time.current + 120)

      expect(ttl).to be_between(118, 120).inclusive
    end

    it "returns 0 when expires_at is nil" do
      expect(described_class.ttl_with_skew(expires_at: nil, skew_seconds: 30)).to eq(0)
    end

    it "returns 0 when the expiry is already in the past" do
      expect(described_class.ttl_with_skew(expires_at: Time.current - 60, skew_seconds: 0)).to eq(0)
    end

    it "returns 0 when the skew is larger than the remaining lease" do
      # 10s remaining, 60s skew => negative, floored to 0.
      expect(described_class.ttl_with_skew(expires_at: Time.current + 10, skew_seconds: 60)).to eq(0)
    end
  end

  # ==========================================================================
  # .fetch — MISS then HIT (the block runs once; the second call is served cached)
  # ==========================================================================
  describe ".fetch cache miss then hit" do
    it "runs the block on a MISS and caches the returned material" do
      calls = 0
      result = described_class.fetch(cache_key) do
        calls += 1
        { material: material, ttl_seconds: 300 }
      end

      expect(calls).to eq(1)
      expect(result).to eq(material_string_keys)
      # The material was actually written to Redis under the namespaced key.
      expect(Powernode::Redis.client.get(full_key)).to be_present
    end

    it "serves the SECOND call from the cache WITHOUT re-running the block" do
      calls = 0
      block = lambda do
        calls += 1
        { material: material, ttl_seconds: 300 }
      end

      first  = described_class.fetch(cache_key, &block)
      second = described_class.fetch(cache_key, &block)

      # The block ran exactly once across both calls — the hit short-circuits it.
      expect(calls).to eq(1)
      expect(first).to eq(material_string_keys)
      # The cached material comes back with STRING keys (JSON round-trip).
      expect(second).to eq(material_string_keys)
    end

    it "floors a small positive ttl to MIN_TTL when storing (still a real cache write)" do
      described_class.fetch(cache_key) { { material: material, ttl_seconds: 1 } }

      client = Powernode::Redis.client
      expect(client.get(full_key)).to be_present
      # ttl_seconds:1 is floored to MIN_TTL (5) for the stored entry.
      expect(client.ttl(full_key)).to be > 1
      expect(client.ttl(full_key)).to be <= described_class::MIN_TTL
    end

    it "raises ArgumentError when no block is given" do
      expect { described_class.fetch(cache_key) }.to raise_error(ArgumentError, /block required/)
    end
  end

  # ==========================================================================
  # Uncacheable — block signals ttl_seconds <= 0 => material returned, NOT cached
  # ==========================================================================
  describe ".fetch with an uncacheable (ttl_seconds <= 0) result" do
    it "returns the material but does NOT write it to the cache" do
      result = described_class.fetch(cache_key) { { material: material, ttl_seconds: 0 } }

      expect(result).to eq(material_string_keys)
      # Nothing was stored — the broker signalled "do not cache".
      expect(Powernode::Redis.client.get(full_key)).to be_nil
    end

    it "re-runs the block on the next call (because nothing was cached)" do
      calls = 0
      block = lambda do
        calls += 1
        { material: material, ttl_seconds: 0 }
      end

      described_class.fetch(cache_key, &block)
      described_class.fetch(cache_key, &block)

      # No cache write happened, so each call recomputes.
      expect(calls).to eq(2)
    end

    it "treats a negative ttl_seconds as uncacheable too" do
      described_class.fetch(cache_key) { { material: material, ttl_seconds: -10 } }

      expect(Powernode::Redis.client.get(full_key)).to be_nil
    end
  end

  # ==========================================================================
  # Nil material — block yields no material => returns nil, nothing cached
  # ==========================================================================
  describe ".fetch when the block yields no material" do
    it "returns nil and caches nothing for a nil material" do
      result = described_class.fetch(cache_key) { { material: nil, ttl_seconds: 300 } }

      expect(result).to be_nil
      expect(Powernode::Redis.client.get(full_key)).to be_nil
    end

    it "returns nil when the block result is not a Hash at all" do
      result = described_class.fetch(cache_key) { nil }

      expect(result).to be_nil
      expect(Powernode::Redis.client.get(full_key)).to be_nil
    end
  end

  # ==========================================================================
  # *** PRIORITY REGRESSION (the MAJOR review fix) ***
  #
  # When the block RAISES, .fetch must let the error PROPAGATE — the exchange is
  # NOT rescued inside BrokerCache (it is left to the broker's own fail-safe,
  # BaseBroker#acquire). Crucially the block is invoked EXACTLY ONCE: the old
  # code re-ran the block on a rescue path, doubling the upstream call
  # (AssumeRole / OAuth token endpoint / Vault dynamic engine) and defeating
  # singleflight. We pin BOTH the propagation AND the single invocation here.
  # ==========================================================================
  describe ".fetch when the block raises (regression: no retry, propagate)" do
    it "lets the error propagate and invokes the block EXACTLY ONCE" do
      calls = 0
      boom = lambda do
        calls += 1
        raise StandardError, "upstream exchange failed"
      end

      expect { described_class.fetch(cache_key, &boom) }
        .to raise_error(StandardError, "upstream exchange failed")

      # The compute happens OUTSIDE any rescue — a failed exchange is NEVER
      # retried inside the cache (that would double the upstream call).
      expect(calls).to eq(1)
    end

    it "caches nothing when the block raises" do
      expect do
        described_class.fetch(cache_key) { raise "exchange blew up" }
      end.to raise_error(RuntimeError, "exchange blew up")

      expect(Powernode::Redis.client.get(full_key)).to be_nil
    end
  end

  # ==========================================================================
  # FAIL-OPEN — a Redis outage must never break the fetch; the block runs once
  # and its material is returned uncached.
  # ==========================================================================
  describe ".fetch fail-open when Redis is unavailable" do
    it "still runs the block once and returns its material when the client raises" do
      # redis_client rescues to nil when Powernode::Redis.client raises, so .fetch
      # falls through to a single compute and returns the material uncached.
      allow(Powernode::Redis).to receive(:client).and_raise(::Redis::CannotConnectError.new("down"))

      calls = 0
      result = described_class.fetch(cache_key) do
        calls += 1
        { material: material, ttl_seconds: 300 }
      end

      expect(calls).to eq(1)
      expect(result).to eq(material_string_keys)
    end

    it "does not retry the block on a Redis outage (single upstream call)" do
      allow(Powernode::Redis).to receive(:client).and_raise(::Redis::CannotConnectError.new("down"))

      calls = 0
      block = lambda do
        calls += 1
        { material: material, ttl_seconds: 300 }
      end

      # Two separate fetches with Redis down: each computes exactly once (nothing
      # is ever cached), so the block has run twice total — never twice per call.
      described_class.fetch(cache_key, &block)
      described_class.fetch(cache_key, &block)

      expect(calls).to eq(2)
    end
  end

  # ==========================================================================
  # SINGLEFLIGHT — a second (concurrent-ish) caller while the key already exists
  # is served the cached value WITHOUT re-running the block. We simulate
  # concurrency WITHOUT threads/sleep by PRE-SEEDING the cache (as the lock
  # winner's write would have), then asserting the contended caller reads it.
  # ==========================================================================
  describe ".fetch singleflight (no threads/sleep)" do
    it "returns the pre-seeded cached value without invoking the block" do
      # Simulate the lock winner having already written the entry: a later caller
      # (the contended path) must collapse onto this cached value, not recompute.
      Powernode::Redis.client.setex(full_key, 60, JSON.generate(material))

      calls = 0
      result = described_class.fetch(cache_key) do
        calls += 1
        { material: { "should" => "not-run" }, ttl_seconds: 300 }
      end

      # The block never ran — the herd converged on the already-cached material.
      expect(calls).to eq(0)
      expect(result).to eq(material_string_keys)
    end

    it "treats a corrupt cached entry as a miss and recomputes once" do
      # A non-JSON / non-Hash entry is parsed as nil (treated as a miss), so the
      # block runs exactly once and the good material replaces it.
      Powernode::Redis.client.setex(full_key, 60, "}{ not json")

      calls = 0
      result = described_class.fetch(cache_key) do
        calls += 1
        { material: material, ttl_seconds: 300 }
      end

      expect(calls).to eq(1)
      expect(result).to eq(material_string_keys)
    end
  end

  # ==========================================================================
  # Constants — pin the cache namespace + TTL floors the impl relies on.
  # ==========================================================================
  describe "constants" do
    it "namespaces all cache + lock keys under ds_cred_broker:" do
      expect(described_class::NAMESPACE).to eq("ds_cred_broker:")
    end

    it "exposes a positive MIN_TTL floor and a positive LOCK_TTL" do
      expect(described_class::MIN_TTL).to be_positive
      expect(described_class::LOCK_TTL).to be_positive
    end
  end
end

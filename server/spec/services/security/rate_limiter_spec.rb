# frozen_string_literal: true

require "rails_helper"

# IMP-3fdaa94f6327. Security::RateLimiter#increment used to INCR, then EXPIRE
# only when the INCR returned 1. Two round trips, and the second was the only
# chance the key ever had to get a TTL: lose it (a timeout, a dropped
# connection, a process killed between the two) and the counter lived forever,
# so the client was rate-limited forever once it crossed the limit.
#
# Against the lane's real Redis: the TTL is the behaviour under test.
RSpec.describe Security::RateLimiter do
  let(:redis) { Powernode::Redis.pooled }
  let(:key) { "rspec-#{SecureRandom.hex(6)}" }
  let(:window) { described_class::RATE_LIMITS[:chat_send][:window] }
  let(:limit) { described_class::RATE_LIMITS[:chat_send][:limit] }
  let(:full_key) { "rate_limit:chat_send:#{key}" }

  after { redis.del(full_key) }

  def check!
    described_class.check!(key: key, category: :chat_send)
  end

  describe "window semantics" do
    it "starts the window on the first request" do
      result = check!

      expect(redis.get(full_key)).to eq("1")
      expect(redis.ttl(full_key)).to be_between(window - 1, window)
      expect(result[:remaining]).to eq(limit - 1)
    end

    it "does not extend the window on later requests (fixed window, not sliding)" do
      check!
      redis.expire(full_key, 10)

      check!

      expect(redis.get(full_key)).to eq("2")
      expect(redis.ttl(full_key)).to be_between(1, 10)
    end

    it "raises once the limit is crossed, with the window's remaining TTL as retry_after" do
      redis.set(full_key, limit, ex: 42)

      expect { check! }.to raise_error(described_class::RateLimitExceeded) { |e| expect(e.retry_after).to be_between(1, 42) }
    end

    it "starts a fresh window once the old one has expired" do
      redis.set(full_key, limit + 1, ex: 42)
      expect { check! }.to raise_error(described_class::RateLimitExceeded)
      redis.del(full_key) # what the TTL's expiry does; no need to sleep

      expect(check![:remaining]).to eq(limit - 1)
      expect(redis.ttl(full_key)).to be_between(window - 1, window)
    end
  end

  describe "a counter whose EXPIRE was lost" do
    it "gets a TTL on the next increment" do
      redis.incr(full_key) # INCR alone: what the old code left behind if EXPIRE never landed
      expect(redis.ttl(full_key)).to eq(-1)

      check!

      expect(redis.get(full_key)).to eq("2")
      expect(redis.ttl(full_key)).to be_between(window - 1, window)
    end

    it "gives a counter stuck over the limit a window TTL, so the limiting ends" do
      redis.set(full_key, limit + 50) # stuck above the limit, no TTL
      expect { check! }.to raise_error(described_class::RateLimitExceeded)

      expect(redis.ttl(full_key)).to be_between(window - 1, window)
    end
  end
end

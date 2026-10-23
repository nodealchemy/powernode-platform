# frozen_string_literal: true

require "rails_helper"

# IMP 01a15724-5c61: three scans did one Redis round trip per key they found (GET + TTL, EXISTS, or
# TTL + 2x GET), so a listing cost O(n) round trips. They now batch the per-key reads, so the count of
# calls on the connection is the same for 5 keys as for 50, and the results are unchanged.
RSpec.describe "Redis round trips on scan-then-read paths" do
  # Counts every top-level call made on the connection it wraps. A pipelined/mget/exists call is one
  # round trip however many keys it carries; a per-key get/ttl/exists? is one each.
  let(:counting_class) do
    Class.new do
      attr_reader :calls

      def initialize(inner)
        @inner = inner
        @calls = []
      end

      def method_missing(name, *args, **kwargs, &block)
        @calls << name
        @inner.public_send(name, *args, **kwargs, &block)
      end

      def respond_to_missing?(name, include_private = false)
        @inner.respond_to?(name, include_private) || super
      end
    end
  end

  def real_connection
    Powernode::Redis.new_client
  end

  after do
    Security::IpBlockStore.reset_pool!
  end

  def wipe(pattern)
    conn = real_connection
    conn.scan_each(match: pattern) { |k| conn.del(k) }
    conn.close
  end

  describe RateLimiting::BaseService do
    let(:ip) { "203.0.113.9" }

    def seed(n, conn)
      (1..n).to_h do |i|
        key = "rate_limit:ctl#{i}:act:ip_#{ip}"
        conn.set(key, i.to_s)
        conn.expire(key, 600 + i)
        [ key, i ]
      end
    end

    before do
      wipe("rate_limit:*")
      allow(Admin::SystemSettings).to receive(:rate_limit).and_return(25)
    end

    after { wipe("rate_limit:*") }

    def measure(n)
      conn = real_connection
      seed(n, conn)
      counter = counting_class.new(conn)
      allow(Powernode::CacheRedis).to receive(:with) { |&blk| blk.call(counter) }
      result = {
        limited: described_class.rate_limited?(ip),
        info: described_class.get_limit_info(ip),
        violations: described_class.send(:count_current_violations)
      }
      [ result, counter.calls ]
    ensure
      conn&.close
    end

    it "returns the same results for any key count, in a fixed number of calls" do
      small_result, small_calls = measure(5)
      wipe("rate_limit:*")
      large_result, large_calls = measure(50)

      expect(small_result[:limited]).to be(false)
      expect(small_result[:violations]).to eq(0)
      expect(small_result[:info].size).to eq(5)
      expect(small_result[:info]["ctl3#act"]).to include(current: 3, limit: 25, remaining: 22)
      expect(small_result[:info]["ctl3#act"][:reset_in]).to be_between(590, 603)

      expect(large_result[:limited]).to be(true) # counters 25..50 reach the limit
      expect(large_result[:violations]).to eq(26)
      expect(large_result[:info].size).to eq(50)
      expect(large_result[:info]["ctl40#act"]).to include(current: 40, limit: 25, remaining: 0)

      expect(large_calls.size).to eq(small_calls.size)
      expect(large_calls).not_to include(:keys, :get, :ttl)
      expect(large_calls).to include(:scan_each)
    end
  end

  describe Security::JwtBlacklistService do
    let(:prefix) { described_class::REDIS_KEY_PREFIX }

    def measure(n)
      conn = real_connection
      live = (1..n).map { |i| "#{prefix}live#{i}" }
      live.each { |k| conn.setex(k, 300, "x") }
      counter = counting_class.new(conn)
      allow(described_class).to receive(:redis).and_return(counter)
      cleaned = described_class.send(:cleanup_expired_redis)
      [ cleaned, counter.calls ]
    ensure
      live&.each { |k| conn.del(k) }
      conn&.close
    end

    before { wipe("#{prefix}*") }
    after { wipe("#{prefix}*") }

    it "checks existence in a fixed number of calls, finding nothing expired among live keys" do
      small_cleaned, small_calls = measure(5)
      large_cleaned, large_calls = measure(50)

      expect([ small_cleaned, large_cleaned ]).to eq([ 0, 0 ])
      expect(large_calls.size).to eq(small_calls.size)
      expect(large_calls).not_to include(:keys, :exists?, :get, :ttl)
    end
  end

  describe Security::IpBlockStore do
    def measure(n)
      conn = real_connection
      (1..n).each do |i|
        ip = "198.51.100.#{i}"
        conn.setex("#{described_class::BLOCK_PREFIX}#{ip}", 100 + i, "1")
        conn.set("#{described_class::OFFENSES_PREFIX}#{ip}", i.to_s) if i.odd?
        conn.set("#{described_class::SUSPICIOUS_PREFIX}#{ip}", (i * 2).to_s) if i % 3 == 0
      end
      counter = counting_class.new(Powernode::Redis.new_client)
      described_class.reset_pool!
      allow(Powernode::Redis).to receive(:new_client).and_return(counter)
      listing = described_class.blocked_ips
      [ listing, counter.calls.dup ]
    ensure
      allow(Powernode::Redis).to receive(:new_client).and_call_original # the helpers below need real ones
      conn&.close
    end

    before { wipe("#{described_class::PREFIX}:*") }
    after { wipe("#{described_class::PREFIX}:*") }

    it "lists blocks with their counters in a fixed number of calls" do
      small, small_calls = measure(5)
      wipe("#{described_class::PREFIX}:*")
      large, large_calls = measure(50)

      expect(small[:blocks].size).to eq(5)
      row = large[:blocks].find { |r| r[:ip] == "198.51.100.9" }
      expect(row).to include(offense_count: 9, suspicious_count: 18)
      expect(row[:ttl_seconds]).to be_between(100, 109)
      expect(large[:blocks].find { |r| r[:ip] == "198.51.100.4" }).to include(offense_count: 0, suspicious_count: 0)
      expect(large[:blocks].size).to eq(50)
      expect(large[:truncated]).to be(false)

      expect(large_calls.size).to eq(small_calls.size)
      expect(large_calls).not_to include(:keys, :get, :ttl)
    end
  end
end

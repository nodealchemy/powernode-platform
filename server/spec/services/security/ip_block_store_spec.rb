# frozen_string_literal: true

require "rails_helper"

# IMP-01a0823e — RequestInspector's DDoS state used to be Rails.cache keys, and
# the hub pins CACHE_STORE=memory_store, so every block and every counter was
# per puma PROCESS and lost on restart. These examples pin the properties that
# made moving it worth doing: shared across processes, durable, and atomic.
RSpec.describe Security::IpBlockStore do
  let(:ip) { "198.51.100.13" }

  # Only this store's own keys: the redis test database is shared by every
  # rspec process on the box, so FLUSHDB here would take out a concurrent run.
  before do
    described_class.with do |redis|
      redis.scan_each(match: "#{described_class::PREFIX}:*") { |key| redis.del(key) }
    end
  end

  describe "blocks" do
    it "records a block that any reader sees, with its real remaining time" do
      expect(described_class.blocked?(ip)).to be(false)

      described_class.block!(ip, duration_seconds: 120)

      expect(described_class.blocked?(ip)).to be(true)
      expect(described_class.block_ttl(ip)).to be_between(110, 120)
    end

    it "refuses a non-positive duration rather than writing a permanent block" do
      expect(described_class.block!(ip, duration_seconds: 0)).to be(false)
      expect(described_class.blocked?(ip)).to be(false)
    end

    it "reports nil TTL for an IP that is not blocked" do
      expect(described_class.block_ttl(ip)).to be_nil
    end

    it "lifts a block and distinguishes 'was blocked' from 'was not'" do
      described_class.block!(ip, duration_seconds: 120)

      expect(described_class.unblock!(ip)).to be(true)
      expect(described_class.blocked?(ip)).to be(false)
      expect(described_class.unblock!(ip)).to be(false)
    end
  end

  describe "counters" do
    # The old implementation read, added one, and wrote back — which loses
    # increments under concurrency, on the exact traffic shape (a flood) the
    # counter exists to measure.
    it "increments atomically and returns the new value" do
      expect(described_class.bump_suspicious(ip, ttl_seconds: 60)).to eq(1)
      expect(described_class.bump_suspicious(ip, ttl_seconds: 60)).to eq(2)
      expect(described_class.suspicious_count(ip)).to eq(2)
    end

    it "does not lose increments across concurrent bumps" do
      threads = 8.times.map { Thread.new { 10.times { described_class.bump_rapid(ip, ttl_seconds: 60) } } }
      threads.each(&:join)

      expect(described_class.rapid_count(ip)).to eq(80)
    end

    it "keeps the offense count for its own long window, separate from the block" do
      described_class.bump_offense(ip)
      described_class.bump_offense(ip)
      described_class.block!(ip, duration_seconds: 60)
      described_class.unblock!(ip)

      expect(described_class.offense_count(ip)).to eq(2)
    end

    it "reads an untouched counter as zero" do
      expect(described_class.suspicious_count(ip)).to eq(0)
      expect(described_class.offense_count(ip)).to eq(0)
    end
  end

  # 2026-09-27 hotfix — the operator was IP-blocked again, this time by
  # rapid_requests. Root cause: #bump re-applied EXPIRE on EVERY call, so as
  # long as requests kept arriving less than ttl_seconds apart the key never
  # expired — a SLIDING window, not the "N requests per ttl_seconds" fixed
  # window RequestInspector's threshold check assumes. Ordinary UI polling,
  # comfortably under 10s apart, accumulated the rapid counter without limit.
  # #bump_rapid and #bump_suspicious both go through #bump and are fixed now;
  # #bump_offense deliberately still slides (its own describe block below).
  describe "fixed-window counters (bump_rapid / bump_suspicious)" do
    it "does not extend the TTL on a later bump — only the first bump in a window sets it" do
      described_class.bump_rapid(ip, ttl_seconds: 10)
      first_ttl = described_class.with { |redis| redis.ttl(described_class::RAPID_PREFIX + ip) }

      sleep 1.5
      described_class.bump_rapid(ip, ttl_seconds: 10)
      second_ttl = described_class.with { |redis| redis.ttl(described_class::RAPID_PREFIX + ip) }

      expect(first_ttl).to be_between(8, 10)
      # A SLIDING window would read ~10 again here (the bug: EXPIRE
      # re-applied on every call). A FIXED window keeps counting down from
      # the first bump regardless of how many more bumps arrive.
      expect(second_ttl).to be < first_ttl
      expect(second_ttl).to be_between(6, 9)
    end

    it "a steady trickle spread across more than one window does not accumulate without limit" do
      # ttl 2s, bumped every 0.5s for ~3s (6 calls) — well under the ttl, the
      # exact shape of the incident (requests arriving faster than the
      # window). A SLIDING window never expires under this traffic and ends
      # at count 6; a FIXED window resets ~1s into this run and again before
      # it ends, so the final count reflects only the bumps since the LAST
      # reset, not the full 6.
      total_bumps = 6
      final_count = nil
      total_bumps.times do
        final_count = described_class.bump_rapid(ip, ttl_seconds: 2)
        sleep 0.5
      end

      expect(final_count).to be < total_bumps
    end

    it "a true burst within one window still reaches the full count" do
      # No sleeps: every bump lands well inside the 60s ttl, so all of them
      # belong to the SAME window regardless of whether it is fixed or
      # sliding — a real flood must still score every hit.
      30.times { described_class.bump_rapid(ip, ttl_seconds: 60) }

      expect(described_class.rapid_count(ip)).to eq(30)
    end

    it "gives a key with no TTL one, rather than leaving it permanent" do
      # Simulates a key that predates this fix (or any other path that could
      # leave the counter without an expiry) — the fallback must not require
      # the key to be freshly created to pick up a TTL.
      described_class.with { |redis| redis.set(described_class::SUSPICIOUS_PREFIX + ip, 5) }
      expect(described_class.with { |redis| redis.ttl(described_class::SUSPICIOUS_PREFIX + ip) }).to eq(-1)

      described_class.bump_suspicious(ip, ttl_seconds: 30)

      ttl = described_class.with { |redis| redis.ttl(described_class::SUSPICIOUS_PREFIX + ip) }
      expect(ttl).to be_between(1, 30)
    end
  end

  # bump_offense is deliberately UNCHANGED by the fixed-window fix above —
  # it is progressive-penalty memory ("how many times has this IP been
  # blocked recently"), not a rate window, so a repeat offender extending
  # its own 7-day memory on every new offense is the intended behavior.
  describe "sliding-window counter (bump_offense)" do
    it "extends its TTL on every bump, unlike the fixed-window counters above" do
      described_class.bump_offense(ip)
      first_ttl = described_class.with { |redis| redis.ttl(described_class::OFFENSES_PREFIX + ip) }

      sleep 1.5
      described_class.bump_offense(ip)
      second_ttl = described_class.with { |redis| redis.ttl(described_class::OFFENSES_PREFIX + ip) }

      # A fixed window would read LOWER here (time elapsed, TTL untouched);
      # bump_offense's sliding behavior instead resets it back up near the
      # full window on every call.
      expect(second_ttl).to be > first_ttl - 1
      expect(second_ttl).to be_between(Security::IpBlockStore::OFFENSE_TTL_SECONDS - 2,
                                        Security::IpBlockStore::OFFENSE_TTL_SECONDS)
    end
  end

  describe "rapid-window claim" do
    it "is won exactly once per window" do
      expect(described_class.claim_rapid_window!(ip, ttl_seconds: 30)).to be(true)
      expect(described_class.claim_rapid_window!(ip, ttl_seconds: 30)).to be(false)
    end

    it "is won by exactly ONE of several racing callers" do
      results = 12.times.map { Thread.new { described_class.claim_rapid_window!(ip, ttl_seconds: 30) } }.map(&:value)

      expect(results.count(true)).to eq(1)
    end
  end

  describe "operator listing" do
    it "lists every blocked IP with its remaining time and history" do
      described_class.bump_offense(ip)
      described_class.block!(ip, duration_seconds: 300)
      described_class.block!("203.0.113.9", duration_seconds: 60)

      result = described_class.blocked_ips

      expect(result[:truncated]).to be(false)
      expect(result[:blocks].map { |b| b[:ip] }).to contain_exactly(ip, "203.0.113.9")
      expect(result[:blocks].first[:ip]).to eq(ip) # longest remaining first
      expect(result[:blocks].first[:offense_count]).to eq(1)
    end

    it "says so when it truncates rather than returning a silently partial answer" do
      3.times { |i| described_class.block!("203.0.113.#{i}", duration_seconds: 60) }

      result = described_class.blocked_ips(limit: 2)

      expect(result[:blocks].size).to eq(2)
      expect(result[:truncated]).to be(true)
    end

    it "is empty when nothing is blocked" do
      expect(described_class.blocked_ips).to eq({ blocks: [], truncated: false })
    end
  end

  # A store that raised would 500 every request (this runs in middleware, ahead
  # of routing); one that answered "blocked" on a backend error would 403 the
  # whole fleet. Both directions fail OPEN.
  describe "when redis is unreachable" do
    before { allow(described_class).to receive(:pool).and_raise(Redis::CannotConnectError, "down") }

    it "answers as if the IP were unknown, and never raises" do
      expect(described_class.blocked?(ip)).to be(false)
      expect(described_class.block_ttl(ip)).to be_nil
      expect(described_class.suspicious_count(ip)).to eq(0)
      expect(described_class.bump_suspicious(ip, ttl_seconds: 60)).to eq(0)
      expect(described_class.claim_rapid_window!(ip, ttl_seconds: 30)).to be(false)
      expect(described_class.unblock!(ip)).to be(false)
      expect(described_class.blocked_ips).to eq({ blocks: [], truncated: false })
    end
  end
end

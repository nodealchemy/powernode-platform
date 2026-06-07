# frozen_string_literal: true

require "rails_helper"

# Real Redis is used here (Powernode::Redis.client) — HostPacer is a thin
# timestamp check (.ready?) + stamp (.touch) over Redis DB 0, so exercising the
# genuine SETEX/GET round-trip is the point. Every key we write is namespaced
# under HostPacer::REDIS_NAMESPACE and torn down in an after hook so examples do
# not bleed into one another (or into other suites sharing the DB).
#
# Elapsed time is simulated by stubbing the pacer's clock source — the private
# #now_epoch reads Time.now.to_f, so advancing a frozen Time.now moves the
# pacer's notion of "now" forward without any Kernel#sleep.
RSpec.describe Ai::DataSources::HostPacer, type: :service do
  let(:host)  { "api.example.com" }
  let(:other) { "other.example.com" }

  # Flush every pacer key we may have created so nothing survives the example.
  after do
    client = Powernode::Redis.client
    keys = client.keys("#{described_class::REDIS_NAMESPACE}:*")
    client.del(*keys) if keys.any?
  rescue StandardError
    nil
  end

  # Freeze the pacer clock at an arbitrary fixed epoch and yield a helper that
  # advances it by N seconds. Stubs Time.now (the impl's #now_epoch source) so
  # .ready?/.touch read a deterministic, sleep-free clock.
  def with_frozen_clock(start = Time.utc(2026, 1, 1, 12, 0, 0))
    current = start
    allow(Time).to receive(:now).and_return(current)
    advance = lambda do |seconds|
      current += seconds
      allow(Time).to receive(:now).and_return(current)
      current
    end
    yield advance
  end

  describe ".ready?" do
    it "is true for a host with no prior touch (first request is always allowed)" do
      expect(described_class.ready?(host, min_interval: 60)).to be(true)
    end

    it "is false within the interval immediately after a touch" do
      with_frozen_clock do
        described_class.touch(host)
        expect(described_class.ready?(host, min_interval: 3_600)).to be(false)
      end
    end

    it "stays false while elapsed time is still under the interval" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        advance.call(30) # 30s of a 60s interval — not yet elapsed
        expect(described_class.ready?(host, min_interval: 60)).to be(false)
      end
    end

    it "becomes true again once the interval has fully elapsed" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        advance.call(61) # past the 60s interval
        expect(described_class.ready?(host, min_interval: 60)).to be(true)
      end
    end

    it "is true exactly at the interval boundary (>= comparison)" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        advance.call(60) # exactly the interval
        expect(described_class.ready?(host, min_interval: 60)).to be(true)
      end
    end

    it "uses the conservative default interval when none is supplied" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        # Default floor is DEFAULT_MIN_INTERVAL_SECONDS (1s): still paced at 0s.
        expect(described_class.ready?(host)).to be(false)
        advance.call(described_class::DEFAULT_MIN_INTERVAL_SECONDS + 0.5)
        expect(described_class.ready?(host)).to be(true)
      end
    end

    context "with a zero / blank / non-positive interval (no pacing)" do
      before do
        with_frozen_clock { described_class.touch(host) }
      end

      it "is always ready for a crawl_delay of 0" do
        expect(described_class.ready?(host, min_interval: 0)).to be(true)
      end

      it "is always ready for a blank ('') interval" do
        expect(described_class.ready?(host, min_interval: "")).to be(true)
      end

      it "is always ready for a nil interval" do
        expect(described_class.ready?(host, min_interval: nil)).to be(true)
      end

      it "is always ready for a negative interval" do
        expect(described_class.ready?(host, min_interval: -5)).to be(true)
      end
    end

    it "is ready when the host itself is blank" do
      expect(described_class.ready?("", min_interval: 3_600)).to be(true)
      expect(described_class.ready?(nil, min_interval: 3_600)).to be(true)
    end

    it "isolates pacing per host — touching A does not pace B" do
      with_frozen_clock do
        described_class.touch(host)
        expect(described_class.ready?(host, min_interval: 3_600)).to be(false)
        expect(described_class.ready?(other, min_interval: 3_600)).to be(true)
      end
    end

    it "paces a URL-ish host and a bare host as the same host (case-insensitive)" do
      with_frozen_clock do
        described_class.touch("https://API.Example.com/v1/items?q=1")
        # Bare, lowercased host should collide with the URL we just stamped.
        expect(described_class.ready?(host, min_interval: 3_600)).to be(false)
      end
    end

    it "fails open (returns true) when Redis raises" do
      allow(Powernode::Redis).to receive(:client).and_raise(::Redis::BaseConnectionError, "down")
      expect(described_class.ready?(host, min_interval: 3_600)).to be(true)
    end
  end

  describe ".touch" do
    it "persists a stamp that a subsequent ready? reads back as paced" do
      with_frozen_clock do
        described_class.touch(host)
        raw = Powernode::Redis.client.get("#{described_class::REDIS_NAMESPACE}:#{host}")
        expect(raw).to be_present
        expect(Float(raw)).to eq(Time.now.to_f)
      end
    end

    it "sets the stamp with the long-lived TTL" do
      with_frozen_clock do
        described_class.touch(host)
        ttl = Powernode::Redis.client.ttl("#{described_class::REDIS_NAMESPACE}:#{host}")
        expect(ttl).to be > 0
        expect(ttl).to be <= described_class::STAMP_TTL_SECONDS
      end
    end

    it "is a no-op for a blank host (writes nothing)" do
      described_class.touch("")
      keys = Powernode::Redis.client.keys("#{described_class::REDIS_NAMESPACE}:*")
      expect(keys).to be_empty
    end

    it "swallows Redis errors and returns nil (best-effort)" do
      allow(Powernode::Redis).to receive(:client).and_raise(::Redis::BaseConnectionError, "down")
      expect { described_class.touch(host) }.not_to raise_error
      expect(described_class.touch(host)).to be_nil
    end
  end

  describe ".seconds_until_ready" do
    it "is 0 for a host with no prior touch" do
      expect(described_class.seconds_until_ready(host, min_interval: 60)).to eq(0)
    end

    it "reports the (ceil'd) remaining seconds within the interval" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        advance.call(20) # 40s remain of a 60s interval
        expect(described_class.seconds_until_ready(host, min_interval: 60)).to eq(40)
      end
    end

    it "is 0 once the interval has elapsed" do
      with_frozen_clock do |advance|
        described_class.touch(host)
        advance.call(61)
        expect(described_class.seconds_until_ready(host, min_interval: 60)).to eq(0)
      end
    end

    it "is 0 for a non-positive interval (no pacing)" do
      with_frozen_clock do
        described_class.touch(host)
        expect(described_class.seconds_until_ready(host, min_interval: 0)).to eq(0)
      end
    end

    it "is 0 (fail-open) when Redis raises" do
      allow(Powernode::Redis).to receive(:client).and_raise(::Redis::BaseConnectionError, "down")
      expect(described_class.seconds_until_ready(host, min_interval: 60)).to eq(0)
    end
  end
end

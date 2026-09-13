# frozen_string_literal: true

require "rails_helper"

# The shared distributed lock, exercised against REAL Redis.
#
# WHY THIS SPEC EXISTS AT ALL. Until PlatformStatusSweepJob (campaign 01a08c9b,
# A2) this concern had ZERO callers — it was reviewed, merged, and never once
# executed. Its `release_lock` called redis-rb's `conn.eval(script, keys:,
# argv:)`, which raises `TypeError: Unsupported command argument type: Array`
# on the `Sidekiq::RedisClientAdapter::CompatClient` Sidekiq 8 hands out, and
# the method rescues StandardError and only logs — so the lock was never
# released and expired by TTL alone, invisibly.
#
# Every example here drives real Redis rather than a double. A double would
# have answered whatever the old call form asked it for and stayed green
# through the entire lifetime of the bug: the defect was in the boundary
# between this code and the real client, which is exactly what a double
# removes.
RSpec.describe DistributedLock do
  # A minimal host object: the concern is meant to be included by a job, and
  # `included do attr_reader ... end` needs a real class to land on.
  let(:holder_class) do
    Class.new do
      include DistributedLock

      def logger
        @logger ||= Logger.new(File::NULL)
      end
    end
  end

  let(:holder) { holder_class.new }
  let(:other_holder) { holder_class.new }
  let(:key) { "spec:distributed_lock:#{SecureRandom.hex(4)}" }
  let(:redis_key) { "lock:#{key}" }

  after { Sidekiq.redis { |c| c.del(redis_key) } }

  def key_exists?
    Sidekiq.redis { |c| c.exists(redis_key) } == 1
  end

  describe "acquiring" do
    it "takes the lock, runs the block, and RELEASES it" do
      ran = false

      result = holder.with_lock(key, ttl: 60) do
        ran = true
        expect(key_exists?).to be(true)
        :block_value
      end

      expect(ran).to be(true)
      expect(result).to eq(:block_value)
      # The arm that was broken for the concern's whole life.
      expect(key_exists?).to be(false)
    end

    it "releases the lock even when the block raises" do
      expect { holder.with_lock(key, ttl: 60) { raise "boom" } }.to raise_error("boom")

      expect(key_exists?).to be(false)
    end

    it "sets the requested TTL rather than leaving the key unbounded" do
      observed = nil
      holder.with_lock(key, ttl: 120) { observed = Sidekiq.redis { |c| c.ttl(redis_key) } }

      expect(observed).to be_between(115, 120)
    end

    it "returns nil and does NOT run the block when the lock is already held" do
      ran = false
      Sidekiq.redis { |c| c.set(redis_key, "someone-else", ex: 60) }

      result = holder.with_lock(key, ttl: 60) { ran = true }

      expect(result).to be_nil
      expect(ran).to be(false)
    end

    it "raises instead of returning nil when asked to" do
      Sidekiq.redis { |c| c.set(redis_key, "someone-else", ex: 60) }

      expect { holder.with_lock(key, ttl: 60, raise_on_failure: true) { :never } }
        .to raise_error(DistributedLock::LockNotAcquiredError, /#{Regexp.escape(redis_key)}/)
    end
  end

  describe "releasing is token-checked — both arms" do
    it "the OWNER's release deletes the key" do
      holder.with_lock(key, ttl: 60) { :ok }

      expect(key_exists?).to be(false)
    end

    it "a NON-OWNER's release leaves the key alone" do
      # Stand in for the dangerous case: a holder whose TTL expired mid-run,
      # after a different process took the lock. A plain DEL would release
      # someone else's lock here and re-admit the overlap.
      holder.with_lock(key, ttl: 60) { :ok }
      Sidekiq.redis { |c| c.set(redis_key, "a-different-process", ex: 60) }

      holder.send(:release_lock)

      expect(Sidekiq.redis { |c| c.get(redis_key) }).to eq("a-different-process")
    end

    it "serialises two holders: the second is refused while the first holds it" do
      inner_result = :not_run

      holder.with_lock(key, ttl: 60) do
        inner_result = other_holder.with_lock(key, ttl: 60) { :should_not_run }
      end

      expect(inner_result).to be_nil
      # ...and once the first released, the second CAN take it.
      expect(other_holder.with_lock(key, ttl: 60) { :now_it_runs }).to eq(:now_it_runs)
    end
  end

  describe "the regression this fix closes" do
    it "the OLD redis-rb call form still raises on this client, so the fix is not cosmetic" do
      # THE RED ARM, kept executable rather than described in a comment. If a
      # future client upgrade makes the old form work again this example fails
      # and someone re-reads the decision, instead of the fix quietly becoming
      # folklore.
      Sidekiq.redis { |c| c.set(redis_key, "tok", ex: 60) }

      expect {
        Sidekiq.redis do |c|
          c.eval(DistributedLock::RELEASE_SCRIPT, keys: [ redis_key ], argv: [ "tok" ])
        end
      }.to raise_error(TypeError, /Unsupported command argument type/)

      # The key survives, which is precisely how the lock leaked.
      expect(key_exists?).to be(true)
    end

    it "the NEW call form deletes it" do
      Sidekiq.redis { |c| c.set(redis_key, "tok", ex: 60) }

      result = Sidekiq.redis do |c|
        c.call("EVAL", DistributedLock::RELEASE_SCRIPT, 1, redis_key, "tok")
      end

      expect(result).to eq(1)
      expect(key_exists?).to be(false)
    end
  end

  describe "#lock_held? and #lock_ttl" do
    it "report a held lock and a free one" do
      expect(holder.lock_held?(key)).to be(false)
      expect(holder.lock_ttl(key)).to be_nil

      Sidekiq.redis { |c| c.set(redis_key, "tok", ex: 60) }

      expect(holder.lock_held?(key)).to be(true)
      expect(holder.lock_ttl(key)).to be_between(55, 60)
    end
  end
end

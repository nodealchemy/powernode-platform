# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Security::JwtBlacklistService.
#
# This documents the CURRENT behavior of the service (it pins existing behavior;
# it does not assert what the behavior *should* be). Where the current behavior
# looks security-relevant or buggy, it is called out in a comment next to the
# example so the pin is not mistaken for an endorsement.
#
# Redis strategy
# --------------
# The service decides between a Redis path and an ActiveRecord (database) path
# via the private `redis_available?` predicate, which is true only when
# `Rails.cache` is a RedisCacheStore. In the test environment the cache store is
# :memory_store, so `redis_available?` is FALSE by default and the service uses
# the database path (the `jwt_blacklists` table / `JwtBlacklist` model, both of
# which exist in this app).
#
# - Database path examples run against the real test database (no stubbing).
# - Redis path examples stub the service's own private seams (`redis_available?`
#   and `redis`) so they round-trip through an `instance_double(Redis)`. This
#   matches the repo's existing convention of stubbing a `Redis` double
#   (see spec/services/ai/provider_circuit_breaker_service_spec.rb) and never
#   touches a real Redis server. The double's `exists?` is wired to return a
#   Boolean to mirror redis-rb 5.x semantics faithfully.
RSpec.describe Security::JwtBlacklistService, type: :service do
  let(:jti) { SecureRandom.uuid }
  let(:future_expiry) { 1.hour.from_now }
  let(:user) { create(:user) }

  # --------------------------------------------------------------------------
  # Database path (the default in the test environment)
  # --------------------------------------------------------------------------
  describe "database path (redis_available? == false, the test default)" do
    it "uses the database path by default in the test env" do
      # Sanity-check the assumption the rest of this block relies on: the test
      # cache store is not Redis, so the service falls back to the DB.
      expect(described_class.send(:redis_available?)).to be(false)
    end

    describe ".blacklist / .blacklisted?" do
      it "returns true and persists a JwtBlacklist row when blacklisting a valid jti" do
        expect do
          expect(described_class.blacklist(jti, future_expiry, reason: "logout", user_id: user.id)).to be(true)
        end.to change(JwtBlacklist, :count).by(1)

        row = JwtBlacklist.find_by(jti: jti)
        expect(row).to have_attributes(
          jti: jti,
          reason: "logout",
          user_id: user.id,
          user_blacklist: false
        )
      end

      it "reports a blacklisted jti as blacklisted? == true" do
        described_class.blacklist(jti, future_expiry)
        expect(described_class.blacklisted?(jti)).to be(true)
      end

      it "reports an unknown jti as blacklisted? == false" do
        expect(described_class.blacklisted?(SecureRandom.uuid)).to be(false)
      end

      it "returns false (and does not persist) for a blank jti" do
        expect do
          expect(described_class.blacklist(nil, future_expiry)).to be(false)
          expect(described_class.blacklist("", future_expiry)).to be(false)
        end.not_to change(JwtBlacklist, :count)
      end

      it "treats blank jti as not blacklisted" do
        expect(described_class.blacklisted?(nil)).to be(false)
        expect(described_class.blacklisted?("")).to be(false)
      end

      it "short-circuits to true WITHOUT persisting when the token is already expired (ttl <= 0)" do
        # calculate_ttl(expires_at) <= 0 => `return true` before any storage.
        expect do
          expect(described_class.blacklist(jti, 5.minutes.ago)).to be(true)
        end.not_to change(JwtBlacklist, :count)

        # ...and because nothing was stored, the (expired) token is NOT considered
        # blacklisted. This is intentional in the impl: an already-expired token
        # cannot be replayed, so it is not tracked.
        expect(described_class.blacklisted?(jti)).to be(false)
      end

      it "does not count a stored-but-expired row as blacklisted (active scope only)" do
        # Persist a row directly with an expiry in the past to exercise the
        # `expires_at > now` filter in blacklisted_in_database?.
        JwtBlacklist.create!(jti: jti, expires_at: 1.minute.ago, reason: "logout")
        expect(described_class.blacklisted?(jti)).to be(false)
      end

      it "swallows a duplicate jti without raising (returns true)" do
        described_class.blacklist(jti, future_expiry)
        # Second blacklist of the same jti hits the unique index -> RecordInvalid,
        # which blacklist_in_database rescues and treats as success.
        expect do
          expect(described_class.blacklist(jti, future_expiry)).to be(true)
        end.not_to change(JwtBlacklist, :count)
      end
    end

    describe ".blacklist_user_tokens" do
      it "creates a user-level blacklist marker row" do
        expect do
          described_class.blacklist_user_tokens(user.id, reason: "account_suspended")
        end.to change(JwtBlacklist, :count).by(1)

        marker = JwtBlacklist.find_by(jti: "user_blacklist_#{user.id}")
        expect(marker).to have_attributes(
          user_id: user.id,
          user_blacklist: true,
          reason: "account_suspended"
        )
        # Marker is given a ~1-year expiry.
        expect(marker.expires_at).to be > 11.months.from_now
      end

      it "is idempotent for the same user (duplicate marker is swallowed)" do
        described_class.blacklist_user_tokens(user.id)
        expect do
          described_class.blacklist_user_tokens(user.id)
        end.not_to change(JwtBlacklist, :count)
      end

      # CHARACTERIZATION OF A GAP: blacklisting a user's tokens records only a
      # per-user marker row keyed by "user_blacklist_<id>". blacklisted?(jti)
      # looks up the *jti* directly and never consults that marker, so an
      # ordinary token jti for a fully-blacklisted user is still reported as
      # NOT blacklisted. (Pinned as current behavior, not endorsed.)
      it "does NOT make an individual token jti blacklisted? for a user-blacklisted user" do
        described_class.blacklist_user_tokens(user.id)
        some_token_jti = SecureRandom.uuid
        expect(described_class.blacklisted?(some_token_jti)).to be(false)
      end
    end

    describe ".cleanup_expired" do
      it "deletes expired rows and returns the number deleted" do
        JwtBlacklist.create!(jti: SecureRandom.uuid, expires_at: 1.minute.ago, reason: "logout")
        JwtBlacklist.create!(jti: SecureRandom.uuid, expires_at: 2.minutes.ago, reason: "logout")
        active = JwtBlacklist.create!(jti: SecureRandom.uuid, expires_at: future_expiry, reason: "logout")

        deleted = described_class.cleanup_expired

        expect(deleted).to eq(2)
        expect(JwtBlacklist.exists?(active.id)).to be(true)
      end

      it "returns 0 when there is nothing expired to clean up" do
        JwtBlacklist.create!(jti: SecureRandom.uuid, expires_at: future_expiry, reason: "logout")
        expect(described_class.cleanup_expired).to eq(0)
      end
    end

    describe ".statistics" do
      it "returns counts and storage: \"database\", counting only active rows in :total" do
        described_class.blacklist(SecureRandom.uuid, future_expiry) # token blacklist
        described_class.blacklist_user_tokens(user.id)              # user blacklist
        JwtBlacklist.create!(jti: SecureRandom.uuid, expires_at: 1.minute.ago, reason: "logout") # expired, excluded

        stats = described_class.statistics

        expect(stats[:storage]).to eq("database")
        expect(stats[:total]).to eq(2) # active only; the expired row is excluded
        expect(stats[:user_blacklists]).to eq(1)
        expect(stats[:token_blacklists]).to eq(1)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Redis path (forced on by stubbing the service's own seams)
  # --------------------------------------------------------------------------
  describe "redis path (redis_available? stubbed true)" do
    let(:redis) { instance_double(Redis) }
    let(:prefix) { Security::JwtBlacklistService::REDIS_KEY_PREFIX }
    # An in-memory store that mirrors just enough of the Redis surface this
    # service touches: setex (store), exists? (Boolean per redis-rb 5.x), and
    # scan_each (key iteration).
    let(:store) { {} }

    before do
      allow(described_class).to receive(:redis_available?).and_return(true)
      allow(described_class).to receive(:redis).and_return(redis)

      allow(redis).to receive(:setex) { |key, _ttl, value| store[key] = value }
      # redis-rb 5.x `exists?` returns a Boolean, not an integer.
      allow(redis).to receive(:exists?) { |key| store.key?(key) }
      allow(redis).to receive(:scan_each) do |match:|
        glob = Regexp.escape(match).gsub('\*', ".*")
        store.keys.select { |k| k.match?(/\A#{glob}\z/) }.each
      end
    end

    describe ".blacklist / .blacklisted?" do
      it "stores the jti via setex with a TTL derived from expires_at" do
        described_class.blacklist(jti, future_expiry, reason: "logout", user_id: user.id)

        key = "#{prefix}#{jti}"
        expect(store).to have_key(key)
        # setex was called with a positive ttl (~1 hour) and a JSON payload.
        expect(redis).to have_received(:setex).with(key, a_value_within(5).of(3600), kind_of(String))
        payload = JSON.parse(store[key])
        expect(payload).to include("reason" => "logout", "user_id" => user.id)
      end

      it "round-trips: a blacklisted jti reads back as blacklisted? == true" do
        described_class.blacklist(jti, future_expiry)
        expect(described_class.blacklisted?(jti)).to be(true)
      end

      it "reports an unknown jti as blacklisted? == false" do
        expect(described_class.blacklisted?(SecureRandom.uuid)).to be(false)
      end

      it "short-circuits an already-expired token to true WITHOUT calling setex" do
        expect(described_class.blacklist(jti, 5.minutes.ago)).to be(true)
        expect(redis).not_to have_received(:setex)
      end
    end

    describe ".blacklist_user_tokens" do
      it "stores a user-level key with a ~1-year TTL" do
        described_class.blacklist_user_tokens(user.id, reason: "account_suspended")

        user_key = "#{prefix}user:#{user.id}"
        expect(store).to have_key(user_key)
        expect(redis).to have_received(:setex).with(user_key, 1.year.to_i, kind_of(String))
        expect(JSON.parse(store[user_key])).to include("reason" => "account_suspended")
      end

      # Same gap as the DB path: blacklisted?(jti) does not consult the per-user
      # key, so an individual token jti is still reported as not blacklisted.
      it "does NOT make an individual token jti blacklisted? for a user-blacklisted user" do
        described_class.blacklist_user_tokens(user.id)
        expect(described_class.blacklisted?(SecureRandom.uuid)).to be(false)
      end
    end

    describe ".statistics" do
      it "partitions scanned keys into user vs token blacklists with storage: \"redis\"" do
        described_class.blacklist(jti, future_expiry)         # token key
        described_class.blacklist_user_tokens(user.id)        # user key

        stats = described_class.statistics

        expect(stats[:storage]).to eq("redis")
        expect(stats[:total]).to eq(2)
        expect(stats[:user_blacklists]).to eq(1)
        expect(stats[:token_blacklists]).to eq(1)
      end
    end

    describe ".cleanup_expired" do
      # CHARACTERIZATION OF A LATENT BUG: cleanup_expired_redis counts keys where
      # `redis.exists?(key) == 0`. Under redis-rb 5.x, `exists?` returns a Boolean
      # (true/false), never the integer 0, so `false == 0` is always false and the
      # method reports 0 cleaned entries regardless of state. Pinned as-is.
      it "returns 0 (relies on Redis TTL auto-expiry; the integer comparison never matches)" do
        described_class.blacklist(jti, future_expiry)
        expect(described_class.cleanup_expired).to eq(0)
      end
    end
  end

  # --------------------------------------------------------------------------
  # Degradation: Redis "available" but the client raises (rescue paths)
  # --------------------------------------------------------------------------
  describe "degradation when the redis client raises" do
    let(:redis) { instance_double(Redis) }

    before do
      allow(described_class).to receive(:redis_available?).and_return(true)
      allow(described_class).to receive(:redis).and_return(redis)
    end

    it "blacklist returns false when the underlying store raises" do
      allow(redis).to receive(:setex).and_raise(StandardError, "redis down")
      expect(described_class.blacklist(jti, future_expiry)).to be(false)
    end

    # SECURITY CONCERN (fail-OPEN): if blacklisted? cannot reach Redis it rescues
    # and returns false, i.e. a token whose jti may well be blacklisted is treated
    # as NOT blacklisted and allowed through. The impl comments this explicitly as
    # "Fail open - if we can't check blacklist, allow the token". Pinned here so a
    # change to fail-closed shows up as a deliberate behavior change.
    it "blacklisted? FAILS OPEN (returns false) when the underlying store raises" do
      allow(redis).to receive(:exists?).and_raise(StandardError, "redis down")
      expect(described_class.blacklisted?(jti)).to be(false)
    end

    it "blacklist_user_tokens returns false when the underlying store raises" do
      allow(redis).to receive(:setex).and_raise(StandardError, "redis down")
      expect(described_class.blacklist_user_tokens(user.id)).to be(false)
    end

    it "statistics returns a zeroed/error shape when the underlying store raises" do
      allow(redis).to receive(:scan_each).and_raise(StandardError, "redis down")
      stats = described_class.statistics
      expect(stats[:total]).to eq(0)
      expect(stats).to have_key(:error)
    end

    it "cleanup_expired swallows store errors (rescue returns the logger result, truthy)" do
      # The rescue body is just `Rails.logger.error(...)`, whose return value
      # (true) becomes the method result -- not a meaningful count. Pinned as-is.
      allow(redis).to receive(:scan_each).and_raise(StandardError, "redis down")
      expect { described_class.cleanup_expired }.not_to raise_error
      expect(described_class.cleanup_expired).to be(true)
    end
  end
end

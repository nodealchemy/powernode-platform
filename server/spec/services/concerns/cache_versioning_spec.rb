# frozen_string_literal: true

require "rails_helper"

# IMP-63a7d2f99c56. Pins the contract every delete_matched call site this
# task migrated now relies on: a scope's keys become unaddressable after
# #bump! without the store ever being asked to enumerate or delete a pattern.
RSpec.describe CacheVersioning do
  let(:store) { ActiveSupport::Cache::MemoryStore.new }

  around do |example|
    Rails.cache.clear
    example.run
  end

  it "builds the same key for the same scope until bumped" do
    first = described_class.key("scope:a", "x", store: store)
    second = described_class.key("scope:a", "x", store: store)

    expect(first).to eq(second)
  end

  it "bumping a scope retires every key previously built for it" do
    scope = "scope:#{SecureRandom.hex(4)}"
    key = described_class.key(scope, "x", store: store)
    store.write(key, "cached-value")
    expect(store.read(key)).to eq("cached-value")

    described_class.bump!(scope, store: store)

    new_key = described_class.key(scope, "x", store: store)
    expect(new_key).not_to eq(key)
    expect(store.read(key)).to eq("cached-value") # orphaned, not deleted — falls out on its own TTL
    expect(store.read(new_key)).to be_nil # unaddressable under the new key
  end

  # REMOVED with IMP-a95f7b6b3e01: the RawCounterStore example and its
  # #read_counter guard. They existed because #bump! went through the store's
  # #increment, and a store whose increment writes a RAW integer (RedisCacheStore's
  # INCRBY) cannot deserialize that payload on a plain #read — version would sit
  # at 0 forever, silently retiring nothing. #bump! no longer increments or reads
  # a counter at all, so that hazard is gone BY CONSTRUCTION rather than handled.
  # The replacement is the source pin below ("does not depend on counter
  # semantics at all"), which reds if either call returns to this file.

  it "does NOT require the store to support #delete_matched" do
    no_delete_matched_store = NoDeleteMatchedCacheStore.new
    scope = "scope:#{SecureRandom.hex(4)}"

    expect {
      described_class.key(scope, "x", store: no_delete_matched_store)
      described_class.bump!(scope, store: no_delete_matched_store)
    }.not_to raise_error
  end

  # ── IMP-a95f7b6b3e01 ──────────────────────────────────────────────────────
  #
  # THE EVICTION RESURRECTION. A monotonic counter is only unique while its own
  # row survives, and the version row is evictable like any other: its id never
  # moves (Entry.write_multi upserts `update_only: [:key, :value, :byte_size]`,
  # entry.rb:29) so it stays in the oldest window forever, and sweep candidates
  # are `order(:id).limit(count * 3)` then `candidate_ids.sample(count)`
  # (entry/expiration.rb:37-49) — a random sample of that window, NOT
  # oldest-first. Routine eviction of a live version row comes from the
  # cache_full branch (max_size: 256 MB, created_at ignored); the age branch
  # runs every pass but only deletes rows past max_age.
  #
  # When it is swept, version reads absent and the NEXT bump starts over at 1 —
  # re-issuing key strings that a previous bump had retired. Security::VaultClient
  # bumps "vault:<path>" on write/delete with a 5-minute read TTL, so the
  # concrete failure is a PRE-ROTATION secret served after a rotation.
  #
  # PREREQUISITE, not a live defect: production pins CACHE_STORE=memory_store,
  # so this forecloses the hazard before solid_cache is adopted rather than
  # fixing something failing today.
  #
  # A non-repeating token cannot do that: no value it produces has ever been
  # produced before, so no previously-issued key becomes addressable again.
  it "never re-issues a retired key after the version entry is evicted" do
    scope = "scope:#{SecureRandom.hex(4)}"
    # Derived, not re-spelled: a hand-copied "#{scope}:cache_version" would keep
    # this example green if version_cache_key were ever renamed, silently
    # degrading it into a plain "two bumps differ" test that cannot fail on the
    # eviction step it claims to model.
    version_key = described_class.send(:version_cache_key, scope)

    key_first = described_class.key(scope, "x", store: store)
    described_class.bump!(scope, store: store)
    key_after_first_bump = described_class.key(scope, "x", store: store)
    expect(key_after_first_bump).not_to eq(key_first)

    # The sweep: the version entry is deleted while the data entries it was
    # versioning are not. This is what expiration.rb does — it deletes rows by
    # id and leaves everything outside the sampled window alone.
    expect(store.read(version_key)).to be_present
    store.delete(version_key)
    expect(store.read(version_key)).to be_nil, "the eviction this example models did not happen"

    described_class.bump!(scope, store: store)
    key_after_eviction = described_class.key(scope, "x", store: store)

    expect(key_after_eviction).not_to eq(key_after_first_bump),
      "the post-eviction bump re-issued a key string a previous bump had already retired — " \
      "anything still cached under it is served again after an explicit invalidation"
    expect(key_after_eviction).not_to eq(key_first)
  end

  # The absence window itself, which is the case a constant "0" sentinel got
  # wrong: an entry cached while no version token exists must not be
  # re-addressable during a LATER absence window, across an intervening bump.
  it "does not reuse one namespace across separate absence windows" do
    scope = "scope:#{SecureRandom.hex(4)}"
    version_key = described_class.send(:version_cache_key, scope)

    store.delete(version_key)
    key_first_absence = described_class.key(scope, "x", store: store)

    described_class.bump!(scope, store: store)
    store.delete(version_key)
    key_second_absence = described_class.key(scope, "x", store: store)

    expect(key_second_absence).not_to eq(key_first_absence),
      "both absence windows built the same key, so anything cached in the first is served " \
      "again in the second — across a bump that was supposed to retire it"
  end

  it "issues a distinct version on every bump, not a resumable sequence" do
    scope = "scope:#{SecureRandom.hex(4)}"

    versions = 3.times.map do
      described_class.bump!(scope, store: store)
      described_class.version(scope, store: store)
    end

    expect(versions.uniq.size).to eq(3)
    # A resumable sequence is exactly what makes eviction dangerous: it can be
    # re-derived from nothing. 1/2/3 would satisfy uniqueness above and still
    # resurrect, so pin that the values are not the sequence.
    expect(versions).not_to eq(%w[1 2 3])
    expect(versions).not_to eq([ 1, 2, 3 ])
  end

  # REPLACES a source-text scan asserting the file contained neither
  # "increment" nor "read_counter". That guard was both vacuous and brittle:
  # `store.write(k, version(scope).to_i + 1)` reintroduces a resumable counter
  # and the scan stays green, while any future COMMENT explaining why
  # #increment is avoided would red it. These are behavioural instead.
  #
  # A store whose #read answers something other than a plain String is the case
  # the deleted RawCounterStore covered and MemoryStore cannot: every other
  # example here runs against MemoryStore or NoDeleteMatchedCacheStore, which
  # is a MemoryStore subclass.
  class OddReadStore < ActiveSupport::Cache::MemoryStore
    attr_accessor :canned_read

    def read(name, options = nil)
      return super unless defined?(@canned_read)

      @canned_read
    end
  end

  it "treats every empty read as 'no token stored', whatever the store answers" do
    [ nil, false, "" ].each do |blank|
      store = OddReadStore.new
      store.canned_read = blank
      scope = "scope:#{SecureRandom.hex(4)}"

      version = described_class.version(scope, store: store)

      expect(version).to be_a(String), "blank read #{blank.inspect} produced #{version.class}"
      expect(version).to be_present
      expect(version).not_to eq("0"), "a shared sentinel is the stale-hit hazard this replaced"
    end
  end

  it "stringifies a non-String token rather than leaking the raw type into a key" do
    store = OddReadStore.new
    store.canned_read = 12345
    scope = "scope:#{SecureRandom.hex(4)}"

    expect(described_class.version(scope, store: store)).to eq("12345")
    expect(described_class.key(scope, "x", store: store)).to eq("#{scope}:v12345:x")
  end

  # The store, not this concern, decides whether a write survives: solid_cache
  # wraps write_entry in failsafe(returning: nil) and RedisCacheStore does the
  # same, so a transient DB/Redis failure answers nil and persists nothing. A
  # bump that did not persist must not report success, or the caller believes an
  # invalidation happened that did not.
  class RefusingWriteStore < ActiveSupport::Cache::MemoryStore
    def write(*) = nil
  end

  it "reports a bump the store did not persist as a failure, loudly" do
    store = RefusingWriteStore.new
    scope = "scope:#{SecureRandom.hex(4)}"

    expect(Rails.logger).to receive(:error).with(/did not persist the version bump/)

    expect(described_class.bump!(scope, store: store)).to be_nil
  end

  it "returns the token when the store does persist it" do
    scope = "scope:#{SecureRandom.hex(4)}"

    token = described_class.bump!(scope, store: store)

    expect(token).to be_present
    expect(described_class.version(scope, store: store)).to eq(token)
  end

  # ── The per-process limitation, stated as a test rather than a comment ────
  #
  # ACCEPTANCE for this task required two processes or a faithful stand-in. Two
  # independent MemoryStore instances ARE that stand-in: MemoryStore holds its
  # entries in the instance, exactly as each puma worker holds its own store.
  # The hub pins CACHE_STORE=memory_store (powernode-hub-backend/manifest.yaml),
  # so this is the live production shape, and it is why the concern's guarantee
  # is per-process there.
  describe "scope of a bump" do
    it "does NOT reach a second process under a per-process store" do
      worker_a = ActiveSupport::Cache::MemoryStore.new
      worker_b = ActiveSupport::Cache::MemoryStore.new
      scope = "scope:#{SecureRandom.hex(4)}"

      key_in_b = described_class.key(scope, "x", store: worker_b)
      described_class.bump!(scope, store: worker_a)

      expect(described_class.key(scope, "x", store: worker_b)).to eq(key_in_b),
        "worker B still builds the pre-bump key — the invalidation did not cross the process " \
        "boundary. This is the documented limitation of CACHE_STORE=memory_store, not a bug in " \
        "the concern; it is pinned so the doc and the behaviour cannot drift apart."
    end

    it "DOES reach a second reader through one shared store" do
      shared = ActiveSupport::Cache::MemoryStore.new
      scope = "scope:#{SecureRandom.hex(4)}"

      key_before = described_class.key(scope, "x", store: shared)
      described_class.bump!(scope, store: shared)

      expect(described_class.key(scope, "x", store: shared)).not_to eq(key_before)
    end
  end

  it "leaves different scopes independent" do
    scope_a = "scope:#{SecureRandom.hex(4)}"
    scope_b = "scope:#{SecureRandom.hex(4)}"
    key_a = described_class.key(scope_a, store: store)

    described_class.bump!(scope_b, store: store)

    expect(described_class.key(scope_a, store: store)).to eq(key_a)
  end
end

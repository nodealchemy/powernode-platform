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

  # IMP-63a7d2f99c56 follow-up (independent review, 2026-09-04). MemoryStore
  # happens to round-trip an incremented counter through a plain #read, which
  # hid this: a store whose #increment writes a RAW integer (RedisCacheStore's
  # INCRBY, and any store using the same convention) cannot deserialize that
  # payload on a normal #read — the coder logs "Unrecognized payload prefix"
  # and answers nil. Version then reads 0 forever, #bump! retires nothing, and
  # EVERY invalidation this task migrated silently stops working, with no
  # error anywhere. ActiveSupport has #read_counter (cache.rb:762) for exactly
  # this reason: it re-reads with raw: true. Asserting through a store that
  # models the raw convention rather than through MemoryStore, which does not.
  class RawCounterStore < ActiveSupport::Cache::MemoryStore
    def initialize(*) = (super; @counters = {})

    # #increment stores the counter UNWRAPPED, as Redis INCRBY does — outside
    # the entry/coder machinery entirely.
    def increment(name, amount = 1, options = nil)
      @counters[normalize_key(name, options)] = counter_at(name, options) + amount
    end

    # A plain #read cannot deserialize that payload: the real coder logs
    # "Unrecognized payload prefix" and answers nil. Only a raw read sees it.
    def read(name, options = nil)
      key = normalize_key(name, options)
      return super unless @counters.key?(key)

      options && options[:raw] ? @counters[key] : nil
    end

    private

    def counter_at(name, options) = (@counters[normalize_key(name, options)] || 0).to_i
  end

  it "reads the version through a counter-aware read, not a plain read" do
    store = RawCounterStore.new
    scope = "scope:#{SecureRandom.hex(4)}"
    key = described_class.key(scope, "x", store: store)

    described_class.bump!(scope, store: store)

    expect(described_class.version(scope, store: store)).to eq(1)
    expect(described_class.key(scope, "x", store: store)).not_to eq(key)
  end

  it "does NOT require the store to support #delete_matched" do
    no_delete_matched_store = NoDeleteMatchedCacheStore.new
    scope = "scope:#{SecureRandom.hex(4)}"

    expect {
      described_class.key(scope, "x", store: no_delete_matched_store)
      described_class.bump!(scope, store: no_delete_matched_store)
    }.not_to raise_error
  end

  it "leaves different scopes independent" do
    scope_a = "scope:#{SecureRandom.hex(4)}"
    scope_b = "scope:#{SecureRandom.hex(4)}"
    key_a = described_class.key(scope_a, store: store)

    described_class.bump!(scope_b, store: store)

    expect(described_class.key(scope_a, store: store)).to eq(key_a)
  end
end

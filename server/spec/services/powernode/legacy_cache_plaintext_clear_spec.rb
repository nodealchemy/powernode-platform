# frozen_string_literal: true

require "rails_helper"

# One-time boot step for the deploy that turns on solid_cache encryption:
# entries written before it are plain text (Vault values on installer hosts
# that already ran solid_cache) and would stay at rest, and be served, until
# evicted. The step empties solid_cache_entries once, behind a SiteSetting
# marker, bounded, and never raises into boot. Emptying a cache is a cold
# start, not data loss.
RSpec.describe Powernode::LegacyCachePlaintextClear do
  # SolidCache::Store runs an expiry batch on a background thread after a write, with probability
  # 2/expiry_batch_size per write (2% by default). Under transactional fixtures that thread shares the
  # example's connection, so a batch landing while run_once! is truncating leaves an entry behind and
  # fails the "empties" example about 1 run in 25. Expiry is not under test: turn it off. (Expiry only
  # deletes; in production it runs on its own connection and the truncate's lock_timeout bounds the
  # contention.)
  before do
    allow_any_instance_of(SolidCache::Store).to receive(:track_writes)
    require Rails.root.join("db/cache_migrate/20260904175500_create_solid_cache_entries.rb").to_s
    ActiveRecord::Migration.suppress_messages { CreateSolidCacheEntries.new.migrate(:up) }
    store = ActiveSupport::Cache.lookup_store(:solid_cache_store)
    store.write("legacy:a", "plain-1")
    store.write("legacy:b", "plain-2")
  end

  def entry_count
    SolidCache::Entry.count
  end

  it "empties solid_cache_entries once and records the marker" do
    expect(entry_count).to eq(2)

    outcome = described_class.run_once!(time_budget: 5)

    expect(outcome.status).to eq(:ran)
    expect(entry_count).to eq(0)
    expect(SiteSetting.get(described_class::DONE_MARKER).to_s).to eq("true")
  end

  it "is a no-op once the marker is set" do
    described_class.run_once!(time_budget: 5)
    ActiveSupport::Cache.lookup_store(:solid_cache_store).write("after", "encrypted-era")

    outcome = described_class.run_once!(time_budget: 5)

    expect(outcome.status).to eq(:done)
    expect(entry_count).to eq(1)
  end

  it "never raises, and leaves the marker unset, when the clear fails" do
    allow(SolidCache::Entry).to receive(:clear_truncate).and_raise(ActiveRecord::LockWaitTimeout, "busy")

    outcome = nil
    expect { outcome = described_class.run_once!(time_budget: 5) }.not_to raise_error

    expect(outcome.status).to eq(:failed)
    expect(SiteSetting.get(described_class::DONE_MARKER).to_s).not_to eq("true")
  end

  it "bounds the clear with statement and lock timeouts" do
    statements = []
    allow(SolidCache::Entry.connection).to receive(:execute).and_wrap_original do |original, sql, *rest|
      statements << sql
      original.call(sql, *rest)
    end

    described_class.run_once!(time_budget: 5)

    expect(statements).to include(a_string_matching(/SET LOCAL statement_timeout = 5000/))
    expect(statements).to include(a_string_matching(/SET LOCAL lock_timeout/))
  end
end

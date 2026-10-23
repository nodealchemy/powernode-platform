# frozen_string_literal: true

require "rails_helper"

# Contract for spec/support/embedding_cache_switch.rb: specs skip the EmbeddingService Redis
# cache by default (it filled the test Redis with ~32 KB/example), and opt in with :embedding_cache.
RSpec.describe "EmbeddingCacheSwitch" do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:service) { Ai::Memory::EmbeddingService.new(account: account, provider: provider) }
  let(:redis) { Powernode::Redis.pooled }
  let(:pattern) { "#{Ai::Memory::EmbeddingService::CACHE_PREFIX}:#{account.id}:*" }

  def cached_keys
    redis.scan_each(match: pattern).to_a
  end

  after { cached_keys.each { |k| redis.del(k) } }

  it "writes no ai:embeddings key to Redis by default" do
    expect(EmbeddingCacheSwitch).not_to be_enabled

    service.generate("default text")
    service.generate_batch(%w[a b])

    expect(cached_keys).to be_empty
  end

  it "writes the cache key when tagged", :embedding_cache do
    service.generate("tagged text")

    expect(cached_keys.size).to eq(1)
  end

  it "writes batch cache keys when tagged", :embedding_cache do
    service.generate_batch(%w[a b])

    expect(cached_keys.size).to eq(2)
  end

  it "honours use_cache: false even when tagged", :embedding_cache do
    service.generate("no cache", use_cache: false)

    expect(cached_keys).to be_empty
  end

  it "enables caching inside with_embedding_cache only" do
    with_embedding_cache { service.generate("block text") }
    expect(cached_keys.size).to eq(1)

    service.generate("after block")
    expect(cached_keys.size).to eq(1)
  end

  it "restores the default after a raise inside the block" do
    expect { with_embedding_cache { raise "boom" } }.to raise_error("boom")

    expect(EmbeddingCacheSwitch).not_to be_enabled
    service.generate("post raise")
    expect(cached_keys).to be_empty
  end

  it "raises on an unbalanced disable" do
    expect { EmbeddingCacheSwitch.disable! }.to raise_error(/unbalanced/)
  end

  it "leaves the cache TTL and prefix unchanged" do
    expect(Ai::Memory::EmbeddingService::CACHE_TTL).to eq(7.days)
    expect(Ai::Memory::EmbeddingService::CACHE_PREFIX).to eq("ai:embeddings")
  end
end

# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# Production solid_cache must encrypt its entries. They hold whatever the app
# caches (OAuth PKCE verifiers among them), and without encryption every value
# is plain text in solid_cache_entries and in every database backup. The guard
# runs at boot in production and refuses to start rather than fall back to
# plain text.
RSpec.describe Powernode::CacheEncryptionGuard do
  let(:solid_store) { instance_double(SolidCache::Store, is_a?: true) }
  let(:keys) { { primary_key: "p" * 32, deterministic_key: "d" * 32, key_derivation_salt: "s" * 32 } }
  let(:encryption_config) { -> { OpenStruct.new(keys) } }

  before do
    allow(solid_store).to receive(:is_a?).with(SolidCache::Store).and_return(true)
  end

  it "passes for an encrypted solid_cache store with all three AR encryption keys" do
    expect { described_class.check!(store: solid_store, encrypt: true, encryption_config: encryption_config) }
      .not_to raise_error
  end

  it "raises when solid_cache is not configured to encrypt" do
    expect { described_class.check!(store: solid_store, encrypt: false, encryption_config: encryption_config) }
      .to raise_error(described_class::Unencrypted, /encrypt: true/)
  end

  %i[primary_key deterministic_key key_derivation_salt].each do |key|
    it "raises when the AR encryption #{key} is missing" do
      config = -> { OpenStruct.new(keys.merge(key => nil)) }

      expect { described_class.check!(store: solid_store, encrypt: true, encryption_config: config) }
        .to raise_error(described_class::Unencrypted, /#{key}/)
    end
  end

  it "raises when the AR encryption keys cannot be resolved at all" do
    config = -> { raise ActiveRecord::Encryption::Errors::Configuration, "missing credential" }

    expect { described_class.check!(store: solid_store, encrypt: true, encryption_config: config) }
      .to raise_error(described_class::Unencrypted, /Configuration/)
  end

  it "does nothing for a store that is not solid_cache" do
    expect { described_class.check!(store: ActiveSupport::Cache::MemoryStore.new, encrypt: false) }
      .not_to raise_error
  end

  it "is configured on: config/cache.yml encrypts in production only" do
    cache_yml = YAML.safe_load(ERB.new(File.read(Rails.root.join("config/cache.yml"))).result, aliases: true)

    expect(cache_yml.dig("production", "encrypt")).to be(true)
    expect(cache_yml.dig("test", "encrypt")).to be_nil
    expect(cache_yml.dig("development", "encrypt")).to be_nil
  end

  it "is wired to run at boot in production" do
    initializer = File.read(Rails.root.join("config/initializers/solid_cache_encryption_guard.rb"))

    expect(initializer).to include("Powernode::CacheEncryptionGuard.check!")
    expect(initializer).to match(/Rails\.env\.production\?/)
  end
end

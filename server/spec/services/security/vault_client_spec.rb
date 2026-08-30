# frozen_string_literal: true

require "rails_helper"

# Characterizes the "Vault unconfigured" fail-safe path on Security::VaultClient.
# NEVER contacts a real Vault server — Vault-unconfigured (VAULT_ROLE_ID /
# VAULT_SECRET_ID absent, AdminSetting empty) is exactly how a Vault-less
# deployment (e.g. ops-hub, by design) runs; credential callers fall back to
# DB encryption in that mode and must never see a raised exception from these
# availability probes.
RSpec.describe Security::VaultClient do
  around do |example|
    described_class.reconfigure!
    example.run
    described_class.reconfigure!
  end

  # Forces the exact "unconfigured" condition #fetch_app_token checks: no
  # AdminSetting-persisted vault_role_id/vault_secret_id, no ENV fallback.
  def with_vault_unconfigured
    allow(described_class).to receive(:admin_setting_config).and_return({})
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("VAULT_ROLE_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("VAULT_SECRET_ID").and_return(nil)
    yield
  end

  describe ".instance" do
    it "raises AuthenticationError constructing the client when Vault is unconfigured " \
       "(documents why .sealed?/.healthy?/.status must rescue it, not just the health check)" do
      with_vault_unconfigured do
        expect { described_class.instance }
          .to raise_error(described_class::AuthenticationError, /VAULT_ROLE_ID not configured/)
      end
    end
  end

  describe ".sealed?" do
    it "returns true (fails closed) instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.sealed? }.not_to raise_error
        expect(result).to be true
      end
    end
  end

  describe ".healthy?" do
    it "returns false instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.healthy? }.not_to raise_error
        expect(result).to be false
      end
    end
  end

  describe ".status" do
    it "returns an unavailable status hash instead of raising when Vault is unconfigured" do
      with_vault_unconfigured do
        result = nil
        expect { result = described_class.status }.not_to raise_error
        expect(result[:available]).to be false
        expect(result[:error]).to match(/VAULT_ROLE_ID not configured/)
      end
    end
  end
  # The key-class contract of #read_secret's return value.
  #
  # The vault gem parses every response with `symbolize_names: true`
  # (vault-0.20.1 lib/vault/client.rb JSON_PARSE_OPTIONS), so
  # #extract_secret_data yields a SYMBOL-keyed Hash. The single-key branch
  # already accepted either spelling (`data[key.to_sym] || data[key.to_s]`);
  # the no-key branch returned the raw Hash, so every string-indexing caller
  # silently read nil. The fixtures below are SYMBOL-keyed on purpose — a
  # string-keyed fixture passes against that bug.
  #
  # NEVER contacts a real Vault server: `token:` skips the AppRole login and the
  # gem's logical reader is doubled.
  describe "#read_secret key normalization" do
    let(:path) { "secret/data/powernode/spec/#{SecureRandom.hex(6)}" }
    # Exactly what the gem hands back for a KV v2 read.
    let(:payload) { { username: "deploy-bot", password: "s3cret" } }

    subject(:client) do
      described_class.new(token: "spec-token").tap do |c|
        logical = double("Vault::Logical")
        allow(logical).to receive(:read).with(path).and_return(
          double("Vault::Secret", data: { data: payload })
        )
        c.instance_variable_set(:@client, double("Vault::Client", logical: logical))
      end
    end

    it "returns a Hash readable by STRING keys from a symbol-keyed Vault payload" do
      result = client.read_secret(path, cache: false)

      expect(result["username"]).to eq("deploy-bot")
      expect(result["password"]).to eq("s3cret")
    end

    it "keeps SYMBOL indexing working for the existing callers that use it" do
      result = client.read_secret(path, cache: false)

      expect(result[:username]).to eq("deploy-bot")
      expect(result[:password]).to eq("s3cret")
    end

    it "exposes exactly the payload's keys, no more and no fewer" do
      expect(client.read_secret(path, cache: false).keys.map(&:to_s).sort)
        .to eq(%w[password username])
    end

    it "normalizes a CACHED value too, so a JSON-coded cache store cannot " \
       "hand a differently-keyed Hash to the second reader" do
      client.read_secret(path, cache: true)
      # Simulate the string-keyed shape a JSON/marshal-coded store round-trips to.
      Rails.cache.write("vault:#{path}:", { "username" => "deploy-bot", "password" => "s3cret" })

      result = client.read_secret(path, cache: true)

      expect(result[:username]).to eq("deploy-bot")
      expect(result["username"]).to eq("deploy-bot")
    ensure
      Rails.cache.delete("vault:#{path}:")
    end

    # `symbolize_names` is deep, so a single-key value that is ITSELF a Hash
    # must not be keyed one way on the cache miss and another on the hit.
    it "normalizes a single-key value that is itself a Hash, on BOTH the cache " \
       "miss and the following hit" do
      nested_path = "secret/data/powernode/spec/#{SecureRandom.hex(6)}"
      logical = double("Vault::Logical")
      allow(logical).to receive(:read).with(nested_path).and_return(
        double("Vault::Secret", data: { data: { oauth: { accessToken: "tok" } } })
      )
      client.instance_variable_set(:@client, double("Vault::Client", logical: logical))

      miss = client.read_secret(nested_path, key: "oauth", cache: true)
      hit  = client.read_secret(nested_path, key: "oauth", cache: true)

      expect(miss["accessToken"]).to eq("tok")
      expect(hit["accessToken"]).to eq("tok")
    ensure
      Rails.cache.delete("vault:#{nested_path}:oauth")
    end

    it "leaves the single-key branch returning the bare VALUE, not a Hash" do
      expect(client.read_secret(path, key: "password", cache: false)).to eq("s3cret")
      expect(client.read_secret(path, key: :password, cache: false)).to eq("s3cret")
    end
  end
end

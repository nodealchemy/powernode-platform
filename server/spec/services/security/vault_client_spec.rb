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

  # IMP-0f914db2c7cf. #probe_secret is the DIAGNOSTIC read behind the
  # credential-path probe on POST /api/v1/admin_settings/vault/test. Its whole
  # reason for existing separately from #read_secret is that a diagnostic must
  # not be able to break the subsystem it diagnoses: read_secret counts a
  # non-retryable Vault::HTTPError (a denied policy on the probed path) against
  # the SHARED `vault` circuit breaker, whose state lives in Rails.cache — three
  # probes of an unreadable path would open it for five minutes for every Vault
  # consumer in the platform.
  describe "#probe_secret" do
    let(:logical) { instance_double(Vault::Logical) }
    let(:client)  { instance_double(Vault::Client, logical: logical) }

    subject(:vault) do
      described_class.allocate.tap do |v|
        v.instance_variable_set(:@client, client)
        v.instance_variable_set(:@cache, Rails.cache)
      end
    end

    def secret_double(data)
      instance_double(Vault::Secret, data: data)
    end

    it "returns the KV v2 payload normalized to string-indexable keys" do
      allow(logical).to receive(:read).with("secret/data/x")
                                      .and_return(secret_double({ data: { username: "bot", password: "pw" } }))

      result = vault.probe_secret("secret/data/x")

      expect(result["username"]).to eq("bot")
      expect(result[:password]).to eq("pw")
    end

    it "raises SecretNotFoundError when the path holds nothing" do
      allow(logical).to receive(:read).with("secret/data/missing").and_return(nil)

      expect { vault.probe_secret("secret/data/missing") }
        .to raise_error(described_class::SecretNotFoundError, /secret\/data\/missing/)
    end

    # The property the whole method exists for.
    it "neither checks nor records circuit-breaker state on a denied read" do
      allow(logical).to receive(:read).and_raise(Vault::HTTPError.new("addr", double(code: 403), [ "permission denied" ]))
      expect(vault).not_to receive(:record_failure)
      expect(vault).not_to receive(:check_circuit_breaker!)

      expect { vault.probe_secret("secret/data/denied") }
        .to raise_error(described_class::ConnectionError)
    end

    it "does not consult the breaker on the success path either" do
      allow(logical).to receive(:read).and_return(secret_double({ data: { password: "pw" } }))
      expect(vault).not_to receive(:check_circuit_breaker!)

      vault.probe_secret("secret/data/x")
    end

    # A probe that reported a shape the next reader would not see is the false
    # reassurance this surface exists to prevent: RepoSyncService reads WITH the
    # 5-minute cache, so without this the sync could keep failing on a payload
    # the operator had already fixed and the probe had already blessed.
    it "invalidates the path's cached entries so the next cached read agrees" do
      allow(logical).to receive(:read).and_return(secret_double({ data: { password: "pw" } }))
      stale_key = vault.send(:cache_key_for, "secret/data/x", nil)
      Rails.cache.write(stale_key, { "password" => "stale" })

      vault.probe_secret("secret/data/x")

      current_key = vault.send(:cache_key_for, "secret/data/x", nil)
      expect(current_key).not_to eq(stale_key) # the stale entry is now unaddressable
      expect(Rails.cache.read(current_key)).to be_nil
    end

    # The ABSENT arm needs it too, and in the more alarming direction: a stale
    # cached payload from before the secret was deleted would let the sync keep
    # succeeding while the probe reports the path missing. The probe disagreeing
    # with the sync is the failure this whole surface exists to prevent, and it
    # does not care which of the two is the optimistic one.
    it "invalidates the cache even when the path turns out to be absent" do
      allow(logical).to receive(:read).and_return(nil)
      stale_key = vault.send(:cache_key_for, "secret/data/gone", nil)
      Rails.cache.write(stale_key, { "password" => "stale" })

      expect { vault.probe_secret("secret/data/gone") }
        .to raise_error(described_class::SecretNotFoundError)

      current_key = vault.send(:cache_key_for, "secret/data/gone", nil)
      expect(current_key).not_to eq(stale_key) # the stale entry is now unaddressable
      expect(Rails.cache.read(current_key)).to be_nil
    end

    # A STATE oracle, not a message oracle. `not_to receive(:record_failure)`
    # only proves this code path does not call that method; it says nothing
    # about the breaker actually staying closed, and it would pass against an
    # implementation that opened the circuit by some other route. Drive the
    # probe past failure_threshold (3) on a missing path and assert the state
    # itself is unchanged.
    it "leaves circuit-breaker state untouched across repeated probes of a missing path" do
      vault.send(:setup_circuit_breaker,
                 resource_id: "vault-probe-oracle-#{SecureRandom.hex(4)}",
                 service_name: "security_vault",
                 config: { failure_threshold: 3, success_threshold: 2, timeout_duration: 30_000,
                           monitoring_window: 300_000, reset_timeout: 300_000 })
      before_state = vault.circuit_state
      allow(logical).to receive(:read).and_return(nil)

      5.times do
        expect { vault.probe_secret("secret/data/gone") }
          .to raise_error(described_class::SecretNotFoundError)
      end

      expect(vault.circuit_state).to eq(before_state)
      expect(vault.circuit_state).to eq("closed")
      expect(vault.circuit_stats[:failure_count]).to eq(0)
    end

    # Same oracle for the arm that actually would have opened it: a denied
    # policy is a non-retryable Vault::HTTPError, which is what read_secret
    # counts toward failure_threshold.
    it "leaves circuit-breaker state untouched across repeated DENIED probes" do
      vault.send(:setup_circuit_breaker,
                 resource_id: "vault-probe-oracle-#{SecureRandom.hex(4)}",
                 service_name: "security_vault",
                 config: { failure_threshold: 3, success_threshold: 2, timeout_duration: 30_000,
                           monitoring_window: 300_000, reset_timeout: 300_000 })
      allow(logical).to receive(:read)
        .and_raise(Vault::HTTPError.new("addr", double(code: 403), [ "permission denied" ]))

      5.times do
        expect { vault.probe_secret("secret/data/denied") }
          .to raise_error(described_class::ConnectionError)
      end

      expect(vault.circuit_state).to eq("closed")
      expect(vault.circuit_stats[:failure_count]).to eq(0)
    end
  end

  # IMP-63a7d2f99c56. #invalidate_cache_for_path called @cache.delete_matched,
  # which the production default store (solid_cache) does not implement — see
  # CacheVersioning's header. @cache is Rails.cache here (VaultClient#initialize
  # sets it from that, same object #probe_secret above stubs directly), so this
  # is not a Vault-specific quirk — it's the same class of defect as the other
  # delete_matched sites this task fixes.
  describe "#invalidate_cache_for_path (private, exercised through #write_secret)" do
    let(:logical) { instance_double(Vault::Logical) }
    let(:client)  { instance_double(Vault::Client, logical: logical) }

    subject(:vault) do
      described_class.allocate.tap do |v|
        v.instance_variable_set(:@client, client)
        v.instance_variable_set(:@cache, NoDeleteMatchedCacheStore.new)
        v.send(:setup_circuit_breaker,
               resource_id: "vault-invalidate-oracle-#{SecureRandom.hex(4)}",
               service_name: "security_vault",
               config: { failure_threshold: 3, success_threshold: 2, timeout_duration: 30_000,
                         monitoring_window: 300_000, reset_timeout: 300_000 })
      end
    end

    it "does not raise invalidating the cache on a store that cannot delete_matched" do
      allow(logical).to receive(:write)

      expect { vault.write_secret("secret/data/x", { password: "pw" }) }.not_to raise_error
    end
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
      Rails.cache.write(client.send(:cache_key_for, path, nil), { "username" => "deploy-bot", "password" => "s3cret" })

      result = client.read_secret(path, cache: true)

      expect(result[:username]).to eq("deploy-bot")
      expect(result["username"]).to eq("deploy-bot")
    ensure
      Rails.cache.delete(client.send(:cache_key_for, path, nil))
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
      Rails.cache.delete(client.send(:cache_key_for, nested_path, "oauth"))
    end

    it "leaves the single-key branch returning the bare VALUE, not a Hash" do
      expect(client.read_secret(path, key: "password", cache: false)).to eq("s3cret")
      expect(client.read_secret(path, key: :password, cache: false)).to eq("s3cret")
    end
  end
end

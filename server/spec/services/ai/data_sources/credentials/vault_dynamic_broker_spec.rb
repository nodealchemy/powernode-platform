# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::VaultDynamicBroker — exchanges a configured Vault
# DYNAMIC-secrets mount path for a SHORT-LIVED credential minted on demand by
# Vault, mapping it into a BrokeredCredential the existing signer layer consumes
# UNCHANGED.
#
# THE CONTRACT under test:
#   broker.acquire(data_source:, base_credential:, config:)
#     -> a BrokeredCredential built from the freshly-read dynamic lease, OR the
#        base_credential UNCHANGED whenever brokering cannot proceed (blank path,
#        no account, empty/garbage Vault response, ANY Vault error). A brokering
#        fault NEVER crashes the fetch pipeline (BaseBroker#acquire fail-safe).
#
# HERMETIC:
#   - the Vault read goes through ::Security::VaultClient.read_secret(path,
#     cache: false) — the TOP-LEVEL Security client the impl actually calls (NOT
#     a new client instance). We stub that class method so no Vault socket opens.
#     read_secret returns ONLY the data Hash (it strips lease envelope metadata),
#     so the lease seconds, when present, ride INSIDE that data Hash under
#     lease_duration / ttl / lease_seconds — which is what the impl digs for.
#   - the cache uses the REAL shared Redis client (Powernode::Redis.client,
#     available in test). Each example flushes the ds_cred_broker:* namespace in a
#     before/after hook so a cached lease never leaks across examples.
#   - the DataSource after_commit knowledge-graph sync (which would otherwise
#     reach embeddings/Redis under DatabaseCleaner :deletion) is stubbed on every
#     factory create.
RSpec.describe Ai::DataSources::Credentials::VaultDynamicBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  # A base credential is irrelevant as a *secret* to this broker (the dynamic
  # engine mints its own), but its fingerprint folds into the cache key. A double
  # responding to the two decrypt readers is enough.
  let(:base_credential) do
    instance_double(
      "Ai::DataSourceCredential",
      decrypted_api_key: "base-key",
      decrypted_api_secret: "base-secret"
    )
  end

  let(:config) { { "vault_path" => "database/creds/readonly-role" } }

  # DB dynamic engine response shape: {username, password} + a lease_duration the
  # impl digs out of the data Hash (VaultClient.read_secret strips the envelope).
  let(:db_secret) do
    { username: "v-token-readonly-abc", password: "s3cr3t-dynamic", lease_duration: 3600 }
  end

  # AWS dynamic engine response shape: {access_key, secret_key, security_token}.
  let(:aws_secret) do
    {
      access_key: "AKIADYNAMIC", secret_key: "awsSecretDynamic",
      security_token: "FwoGDYNAMICtoken", lease_duration: 1800
    }
  end

  # Stub the TOP-LEVEL Security Vault client read the impl calls. Asserts the
  # cache: false flag is passed so a short-lived lease is not pinned by
  # VaultClient's generic 5-minute KV cache.
  def stub_vault_read(returns: nil, raises: nil)
    if raises
      allow(::Security::VaultClient).to receive(:read_secret).and_raise(raises)
    else
      allow(::Security::VaultClient).to receive(:read_secret).and_return(returns)
    end
  end

  # Scrub the broker cache namespace (real Redis) so a lease from one example can
  # never satisfy the next.
  def flush_broker_cache!
    client = Powernode::Redis.client
    return unless client

    keys = client.keys("#{Ai::DataSources::Credentials::BrokerCache::NAMESPACE}*")
    client.del(*keys) if keys.any?
  rescue StandardError
    nil
  end

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    flush_broker_cache!
  end

  after { flush_broker_cache! }

  # ==========================================================================
  # Happy path — DB dynamic engine (username/password)
  # ==========================================================================
  describe "#acquire (DB dynamic engine)" do
    before { stub_vault_read(returns: db_secret) }

    it "reads the configured vault_path with cache: false" do
      expect(::Security::VaultClient).to receive(:read_secret)
        .with("database/creds/readonly-role", cache: false)
        .and_return(db_secret)

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
    end

    it "returns a BrokeredCredential (not the base credential)" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result).not_to eq(base_credential)
    end

    it "maps the dynamic username into the primary key and password into the secret" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      # decrypted_api_key reads api_key first (DB username is exposed there).
      expect(result.decrypted_api_key).to eq("v-token-readonly-abc")
      expect(result.decrypted_api_secret).to eq("s3cr3t-dynamic")
      # The explicit DB spellings are also reachable via #[].
      expect(result["username"]).to eq("v-token-readonly-abc")
      expect(result["password"]).to eq("s3cr3t-dynamic")
    end

    it "derives expires_at from the lease (≈ now + lease_duration)" do
      freeze_time do
        result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

        expect(result.expires_at).to be_within(2.seconds).of(Time.current + 3600.seconds)
      end
    end

    it "caches the lease across calls (Vault read only once for a swarm)" do
      expect(::Security::VaultClient).to receive(:read_secret).once.and_return(db_secret)

      first = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      second = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(first.decrypted_api_key).to eq("v-token-readonly-abc")
      expect(second.decrypted_api_key).to eq("v-token-readonly-abc")
    end
  end

  # ==========================================================================
  # Happy path — AWS dynamic engine (access_key/secret_key/security_token)
  # ==========================================================================
  describe "#acquire (AWS dynamic engine)" do
    let(:config) { { "vault_path" => "aws/creds/s3-reader" } }

    before { stub_vault_read(returns: aws_secret) }

    it "maps access_key/secret_key into the AWS spellings the Sigv4 signer reads" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.decrypted_api_key).to eq("AKIADYNAMIC")          # via access_key_id
      expect(result.decrypted_api_secret).to eq("awsSecretDynamic")  # via secret_access_key
      expect(result["access_key_id"]).to eq("AKIADYNAMIC")
      expect(result["secret_access_key"]).to eq("awsSecretDynamic")
    end

    it "normalizes security_token onto the session_token key Sigv4Signer reads" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result["session_token"]).to eq("FwoGDYNAMICtoken")
      expect(result["security_token"]).to eq("FwoGDYNAMICtoken")
    end
  end

  # ==========================================================================
  # TTL / skew
  # ==========================================================================
  describe "skew handling" do
    before { stub_vault_read(returns: db_secret) }

    it "trims the CACHE TTL by skew_seconds while keeping the absolute expiry intact" do
      cfg = config.merge("skew_seconds" => 120)

      freeze_time do
        result = broker.acquire(data_source: data_source, base_credential: base_credential, config: cfg)

        # Absolute expiry is Vault's real expiry (skew is NOT applied here).
        expect(result.expires_at).to be_within(2.seconds).of(Time.current + 3600.seconds)

        # The stored Redis TTL is (lease - skew), trimmed: ~ 3600 - 120 = 3480.
        client = Powernode::Redis.client
        key = client.keys("#{Ai::DataSources::Credentials::BrokerCache::NAMESPACE}*")
          .reject { |k| k.include?("lock:") }
          .first
        expect(key).to be_present
        ttl = client.ttl(key)
        expect(ttl).to be > 0
        expect(ttl).to be <= (3600 - 120)
      end
    end

    it "defaults skew to DEFAULT_SKEW_SECONDS when none is configured" do
      expect(described_class::DEFAULT_SKEW_SECONDS).to eq(30)

      freeze_time do
        broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

        client = Powernode::Redis.client
        key = client.keys("#{Ai::DataSources::Credentials::BrokerCache::NAMESPACE}*")
          .reject { |k| k.include?("lock:") }
          .first
        ttl = client.ttl(key)
        expect(ttl).to be <= (3600 - 30)
      end
    end
  end

  # ==========================================================================
  # No-lease responses — material returned UNCACHED, re-read each fetch
  # ==========================================================================
  describe "#acquire when Vault advertises no lease" do
    let(:no_lease_secret) { { username: "v-token-noexpiry", password: "no-lease-secret" } }

    before { stub_vault_read(returns: no_lease_secret) }

    it "still returns a BrokeredCredential with a nil expiry" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result.decrypted_api_key).to eq("v-token-noexpiry")
      expect(result.expires_at).to be_nil
    end

    it "does NOT cache the lease (next call re-reads Vault)" do
      expect(::Security::VaultClient).to receive(:read_secret).twice.and_return(no_lease_secret)

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
    end
  end

  # ==========================================================================
  # Degrade paths — fail-safe to base credential, fetch never crashes
  # ==========================================================================
  describe "#acquire degrades to the base credential" do
    it "when vault_path is blank (no Vault read attempted)" do
      expect(::Security::VaultClient).not_to receive(:read_secret)

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: { "vault_path" => "" })

      expect(result).to eq(base_credential)
    end

    it "when config carries no vault_path key at all" do
      expect(::Security::VaultClient).not_to receive(:read_secret)

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: {})

      expect(result).to eq(base_credential)
    end

    it "when the data source has no account (cannot scope/attribute the lease)" do
      accountless = instance_double("Ai::DataSource", id: SecureRandom.uuid, account: nil, slug: "no-acct")
      expect(::Security::VaultClient).not_to receive(:read_secret)

      result = broker.acquire(data_source: accountless, base_credential: base_credential, config: config)

      expect(result).to eq(base_credential)
    end

    it "when Vault returns an empty hash (no dynamic material)" do
      stub_vault_read(returns: {})

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to eq(base_credential)
    end

    it "when Vault returns a hash with no recognizable credential fields" do
      stub_vault_read(returns: { lease_duration: 3600, unrelated: "value" })

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to eq(base_credential)
    end

    it "when the Vault read raises (sealed/unavailable) — never propagates" do
      stub_vault_read(raises: ::Security::VaultClient::ConnectionError.new("vault sealed"))

      result = nil
      expect do
        result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      end.not_to raise_error
      expect(result).to eq(base_credential)
    end

    it "degrades to nil cleanly when base_credential is nil and Vault errors" do
      stub_vault_read(raises: ::Security::VaultClient::VaultError.new("boom"))

      result = broker.acquire(data_source: data_source, base_credential: nil, config: config)

      expect(result).to be_nil
    end
  end

  # ==========================================================================
  # Account isolation in the cache key
  # ==========================================================================
  describe "cache key account scoping" do
    it "does not share a lease across two accounts on the same vault_path" do
      account_b = create(:account)
      ds_b = create(:ai_data_source, account: account_b)

      # Each account's first fetch must hit Vault independently — leases never
      # cross account boundaries in Redis.
      expect(::Security::VaultClient).to receive(:read_secret).twice.and_return(db_secret)

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      broker.acquire(data_source: ds_b, base_credential: base_credential, config: config)
    end
  end

  # ==========================================================================
  # SECURITY — minted secret material is NEVER logged
  # ==========================================================================
  describe "secret never logged" do
    it "emits a non-secret audit line carrying neither username nor password" do
      stub_vault_read(returns: db_secret)
      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      joined = logged.join("\n")
      expect(joined).to include("broker=vault_dynamic")
      expect(joined).to include("outcome=acquired")
      expect(joined).not_to include("v-token-readonly-abc")
      expect(joined).not_to include("s3cr3t-dynamic")
    end

    it "logs no secret material across ANY logger level on the happy path" do
      stub_vault_read(returns: aws_secret)
      captured = []
      %i[debug info warn error fatal].each do |lvl|
        allow(Rails.logger).to receive(lvl) { |msg| captured << msg.to_s }
      end

      broker.acquire(data_source: data_source, base_credential: base_credential, config: { "vault_path" => "aws/creds/s3-reader" })

      blob = captured.join("\n")
      expect(blob).not_to include("AKIADYNAMIC")
      expect(blob).not_to include("awsSecretDynamic")
      expect(blob).not_to include("FwoGDYNAMICtoken")
    end

    it "BrokeredCredential#inspect redacts the material (only field names + expiry)" do
      stub_vault_read(returns: db_secret)
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.inspect).not_to include("s3cr3t-dynamic")
      expect(result.inspect).not_to include("v-token-readonly-abc")
      expect(result.inspect).to include("fields=")
    end
  end

  # ==========================================================================
  # Registry token
  # ==========================================================================
  describe "#broker_type" do
    it "is the canonical registry token" do
      expect(broker.send(:broker_type)).to eq("vault_dynamic")
    end
  end
end

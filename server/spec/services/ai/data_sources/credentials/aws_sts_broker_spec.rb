# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::AwsStsBroker — dynamic credential broker that
# exchanges the BASE credential's long-lived AWS keys for SHORT-LIVED STS
# credentials via AssumeRole, just before the signed fetch.
#
# PUBLIC CONTRACT (BaseBroker#acquire template):
#   broker.acquire(data_source:, base_credential:, config:)
#     -> a BrokeredCredential exposing the temporary session
#        (#decrypted_api_key => access_key_id, #decrypted_api_secret =>
#         secret_access_key, #["session_token"]), OR base_credential unchanged
#        on any misconfiguration / failure (fail-safe degrade).
#
# HERMETIC:
#   - Aws::STS::Client.new is stubbed to return a client double whose
#     #assume_role(params) yields a response double#credentials (the STS
#     short-lived material). NO real STS/network/AWS call is ever made.
#   - BrokerCache is Redis-backed against the REAL shared client
#     (Powernode::Redis.client, available in test). Each example flushes the
#     "ds_cred_broker:" namespace in a before/after hook so a cached session from
#     one example can never satisfy the next.
RSpec.describe Ai::DataSources::Credentials::AwsStsBroker, type: :service do
  subject(:broker) { described_class.new }

  # A persisted source so cache_key_for has a stable #id; the after_commit KG
  # sync is stubbed so the factory create stays hermetic under DatabaseCleaner.
  let(:account) { create(:account) }
  let(:data_source) do
    create(:ai_data_source, account: account, slug: "sts_src",
                            api_base_url: "https://private.execute-api.example.com")
  end

  # The BASE credential whose AWS keys are used to CALL AssumeRole. A bare double
  # satisfying the signer contract (decrypted_api_key / decrypted_api_secret) is
  # the canonical broker input.
  let(:base_credential) do
    instance_double("Ai::DataSourceCredential",
                    decrypted_api_key: "AKIAEXAMPLE", decrypted_api_secret: "secret")
  end

  let(:role_arn) { "arn:aws:iam::123:role/r" }
  let(:config) { { "role_arn" => role_arn } }

  # An absolute STS expiry the SDK would return on #credentials.expiration.
  let(:sts_expiration) { Time.current + 3600 }

  # An Aws::STS::Types::Credentials stand-in: only the four fields the broker
  # reads (access_key_id/secret_access_key/session_token/expiration) are present.
  def sts_credentials(access_key_id: "ASIATEMP", secret_access_key: "tmpsecret",
                      session_token: "SESSIONTOKEN", expiration: sts_expiration)
    instance_double("Aws::STS::Types::Credentials",
                    access_key_id: access_key_id, secret_access_key: secret_access_key,
                    session_token: session_token, expiration: expiration)
  end

  # Stub Aws::STS::Client.new to return a client double whose #assume_role(params)
  # returns a response double#credentials. Returns BOTH the client double and the
  # captured opts hash passed to .new so the no-endpoint-override assertion can
  # inspect it. By default any opts are accepted.
  def stub_sts(credentials: nil, error: nil)
    credentials ||= sts_credentials
    client = instance_double("Aws::STS::Client")
    if error
      allow(client).to receive(:assume_role).and_raise(error)
    else
      response = instance_double("Aws::STS::Types::AssumeRoleResponse", credentials: credentials)
      allow(client).to receive(:assume_role).and_return(response)
    end
    allow(Aws::STS::Client).to receive(:new).and_return(client)
    client
  end

  # Scrub the shared brokered-credential namespace so a cached STS session from
  # one example can never leak into the next.
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
  # Happy path — AssumeRole material is exposed through the signer contract
  # ==========================================================================
  describe "happy path" do
    before { stub_sts }

    it "returns a BrokeredCredential (not the base credential)" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result).not_to equal(base_credential)
    end

    it "exposes the STS access_key_id as #decrypted_api_key" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.decrypted_api_key).to eq("ASIATEMP")
    end

    it "exposes the STS secret_access_key as #decrypted_api_secret" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.decrypted_api_secret).to eq("tmpsecret")
    end

    it "exposes the STS session_token via #[](\"session_token\")" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result["session_token"]).to eq("SESSIONTOKEN")
    end

    it "carries the absolute STS expiry onto the BrokeredCredential" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.expires_at).to be_within(1.second).of(sts_expiration)
    end

    it "calls AssumeRole with the configured role_arn" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(client).to have_received(:assume_role).with(hash_including(role_arn: role_arn))
    end

    it "authenticates the STS client with the BASE credential's AWS keys" do
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Aws::STS::Client).to have_received(:new).with(
        hash_including(access_key_id: "AKIAEXAMPLE", secret_access_key: "secret")
      )
    end
  end

  # ==========================================================================
  # SECURITY: a config-supplied endpoint override is NEVER honored (anti-SSRF)
  # ==========================================================================
  describe "STS endpoint override is rejected (security)" do
    it "does NOT pass any :endpoint to Aws::STS::Client.new even when config carries one" do
      stub_sts
      malicious = config.merge("endpoint" => "http://169.254.169.254/")

      broker.acquire(data_source: data_source, base_credential: base_credential, config: malicious)

      # The SDK call MUST hit the fixed/regional AWS STS endpoint — config can
      # never redirect it (that would reintroduce SSRF).
      expect(Aws::STS::Client).to have_received(:new) do |opts|
        expect(opts).not_to have_key(:endpoint)
        expect(opts).not_to have_key("endpoint")
      end
    end

    it "supplies a default region when none is configured (global STS service)" do
      stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Aws::STS::Client).to have_received(:new).with(hash_including(region: "us-east-1"))
    end
  end

  # ==========================================================================
  # DurationSeconds clamp into the STS-allowed window (900 .. 43200)
  # ==========================================================================
  describe "duration clamp" do
    it "clamps an over-range duration_seconds down to the STS max (43200)" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("duration_seconds" => 999_999))

      expect(client).to have_received(:assume_role).with(hash_including(duration_seconds: 43_200))
    end

    it "clamps an under-range duration_seconds up to the STS min (900)" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("duration_seconds" => 60))

      expect(client).to have_received(:assume_role).with(hash_including(duration_seconds: 900))
    end

    it "defaults to 3600 when duration_seconds is absent" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(client).to have_received(:assume_role).with(hash_including(duration_seconds: 3600))
    end

    it "defaults to 3600 when duration_seconds is non-positive" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("duration_seconds" => 0))

      expect(client).to have_received(:assume_role).with(hash_including(duration_seconds: 3600))
    end
  end

  # ==========================================================================
  # Degrade paths — misconfiguration returns the base credential UNCHANGED
  # and never calls STS.
  # ==========================================================================
  describe "degrade on misconfiguration" do
    it "returns the base credential and never calls STS when role_arn is blank" do
      allow(Aws::STS::Client).to receive(:new)

      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "role_arn" => "" })

      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential and never calls STS when role_arn is missing entirely" do
      allow(Aws::STS::Client).to receive(:new)

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: {})

      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential when the base access key is blank" do
      allow(Aws::STS::Client).to receive(:new)
      keyless = instance_double("Ai::DataSourceCredential",
                                decrypted_api_key: nil, decrypted_api_secret: "secret")

      result = broker.acquire(data_source: data_source, base_credential: keyless, config: config)

      expect(result).to equal(keyless)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential when the base secret is blank" do
      allow(Aws::STS::Client).to receive(:new)
      secretless = instance_double("Ai::DataSourceCredential",
                                   decrypted_api_key: "AKIAEXAMPLE", decrypted_api_secret: "")

      result = broker.acquire(data_source: data_source, base_credential: secretless, config: config)

      expect(result).to equal(secretless)
      expect(Aws::STS::Client).not_to have_received(:new)
    end
  end

  # ==========================================================================
  # Cache key rotation — rotating the BASE secret busts the cache so a fresh
  # AssumeRole is performed (the fingerprint covers BOTH base keys).
  # ==========================================================================
  describe "cache key changes when the base secret rotates" do
    it "performs a second AssumeRole when the base secret changes (cache busted)" do
      client = stub_sts

      first_cred = instance_double("Ai::DataSourceCredential",
                                   decrypted_api_key: "AKIAEXAMPLE", decrypted_api_secret: "secret-v1")
      second_cred = instance_double("Ai::DataSourceCredential",
                                    decrypted_api_key: "AKIAEXAMPLE", decrypted_api_secret: "secret-v2")

      broker.acquire(data_source: data_source, base_credential: first_cred, config: config)
      broker.acquire(data_source: data_source, base_credential: second_cred, config: config)

      # Distinct base secrets => distinct cache keys => BOTH miss => two STS calls.
      expect(client).to have_received(:assume_role).twice
    end

    it "reuses the cached session on a repeat call with the SAME base secret (one STS call)" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      # Identical base keys + role => same cache key => second call is a HIT.
      expect(client).to have_received(:assume_role).once
    end
  end

  # ==========================================================================
  # Fail-safe — any STS error degrades to the base credential (never raises).
  # ==========================================================================
  describe "STS error fail-safe" do
    it "returns the base credential unchanged when AssumeRole raises" do
      stub_sts(error: StandardError.new("AccessDenied"))

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to equal(base_credential)
    end

    it "does not raise out of #acquire on an STS service error" do
      stub_sts(error: RuntimeError.new("throttled"))

      expect do
        broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      end.not_to raise_error
    end
  end

  # ==========================================================================
  # Works with the real :ai_data_source_credential factory as the base cred
  # (decrypted_api_key/secret resolve off the encrypted attributes).
  # ==========================================================================
  describe "with a persisted base credential" do
    it "brokers a session from a real DataSourceCredential's decrypted keys" do
      client = stub_sts
      persisted = create(:ai_data_source_credential, :with_secret, account: account,
                                                                   data_source: data_source)

      result = broker.acquire(data_source: data_source, base_credential: persisted, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result.decrypted_api_key).to eq("ASIATEMP")
      expect(client).to have_received(:assume_role).with(
        hash_including(role_arn: role_arn)
      )
      expect(Aws::STS::Client).to have_received(:new).with(
        hash_including(access_key_id: "test-api-key", secret_access_key: "test-api-secret")
      )
    end
  end
end

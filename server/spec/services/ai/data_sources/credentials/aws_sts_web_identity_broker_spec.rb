# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::AwsStsWebIdentityBroker — KEYLESS workload-identity
# broker that exchanges an OIDC/JWT web-identity token for SHORT-LIVED AWS STS
# credentials via AssumeRoleWithWebIdentity, just before the signed fetch. NO
# static AWS keys are required — the workload proves identity with a federated
# OIDC token. Subclasses AwsStsBroker; only token sourcing, the (unauthenticated)
# STS exchange, and the cache key differ.
#
# PUBLIC CONTRACT (BaseBroker#acquire template):
#   broker.acquire(data_source:, base_credential:, config:)
#     -> a BrokeredCredential exposing the temporary session (same shape as
#        AwsStsBroker: #decrypted_api_key => access_key_id, #decrypted_api_secret
#        => secret_access_key, #["session_token"]), OR base_credential unchanged
#        on misconfiguration (no role_arn / no resolvable token) / failure.
#
# HERMETIC:
#   - Aws::STS::Client.new is stubbed to a client double whose
#     #assume_role_with_web_identity(params) yields a response double#credentials.
#   - A token_url fetch is routed through the SSRF-guarded connection
#     (HttpConnectionFactory.build); .build is stubbed to a Faraday connection
#     double whose #run_request returns a response double (status:/body/success?).
#     NO real STS / OIDC / network call is ever made.
#   - BrokerCache uses the REAL shared Redis client; each example flushes the
#     "ds_cred_broker:" namespace so a cached session never leaks across examples.
RSpec.describe Ai::DataSources::Credentials::AwsStsWebIdentityBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:account) { create(:account) }
  let(:data_source) do
    create(:ai_data_source, account: account, slug: "wi_src",
                            api_base_url: "https://private.execute-api.example.com")
  end

  # KEYLESS: base_credential is ignored for the exchange but still passed through
  # and returned unchanged on any degrade path. A nil base is the realistic
  # workload-identity case (no stored AWS keys at all).
  let(:base_credential) { nil }

  let(:role_arn) { "arn:aws:iam::123:role/r" }
  let(:web_identity_token) { "header.payload.signature" }
  let(:config) { { "role_arn" => role_arn, "web_identity_token" => web_identity_token } }

  let(:sts_expiration) { Time.current + 3600 }

  def sts_credentials(access_key_id: "ASIAWEBID", secret_access_key: "tmpsecret",
                      session_token: "WISESSIONTOKEN", expiration: sts_expiration)
    instance_double("Aws::STS::Types::Credentials",
                    access_key_id: access_key_id, secret_access_key: secret_access_key,
                    session_token: session_token, expiration: expiration)
  end

  # Stub Aws::STS::Client.new -> client double whose #assume_role_with_web_identity
  # returns a response double#credentials. Returns the client double for argument /
  # call-count assertions.
  def stub_sts(credentials: nil, error: nil)
    credentials ||= sts_credentials
    client = instance_double("Aws::STS::Client")
    if error
      allow(client).to receive(:assume_role_with_web_identity).and_raise(error)
    else
      response = instance_double("Aws::STS::Types::AssumeRoleWithWebIdentityResponse",
                                 credentials: credentials)
      allow(client).to receive(:assume_role_with_web_identity).and_return(response)
    end
    allow(Aws::STS::Client).to receive(:new).and_return(client)
    client
  end

  # A Faraday-ish response for the SSRF-guarded token_url fetch: the impl reads
  # #success? then #body.
  def http_response(status: 200, body: "fetched.jwt.token")
    instance_double("Faraday::Response", success?: (200..299).cover?(status),
                                         status: status, body: body)
  end

  # Stub the SSRF-guarded connection (HttpConnectionFactory.build) so a token_url
  # fetch never opens a socket. validate_url! (called by broker_http_connection
  # for resolve-and-pin) is neutralised. Returns the connection double.
  def stub_token_http(response: nil)
    response ||= http_response
    conn = instance_double("Faraday::Connection")
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    conn
  end

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
  # Happy path — inline web_identity_token exchanged for an STS session
  # ==========================================================================
  describe "happy path (inline web_identity_token)" do
    before { stub_sts }

    it "returns a BrokeredCredential (not the base credential)" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
    end

    it "exposes the STS session through the signer contract" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.decrypted_api_key).to eq("ASIAWEBID")
      expect(result.decrypted_api_secret).to eq("tmpsecret")
      expect(result["session_token"]).to eq("WISESSIONTOKEN")
    end

    it "carries the absolute STS expiry onto the BrokeredCredential" do
      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result.expires_at).to be_within(1.second).of(sts_expiration)
    end

    it "calls AssumeRoleWithWebIdentity with the role_arn and the inline token" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(client).to have_received(:assume_role_with_web_identity).with(
        hash_including(role_arn: role_arn, web_identity_token: web_identity_token)
      )
    end

    it "is KEYLESS — works with a nil base credential and never reads AWS keys off it" do
      result = broker.acquire(data_source: data_source, base_credential: nil, config: config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(result.decrypted_api_key).to eq("ASIAWEBID")
    end
  end

  # ==========================================================================
  # SECURITY: the STS client is UNAUTHENTICATED (credentials: false) and never
  # honors a config endpoint override.
  # ==========================================================================
  describe "STS client construction (security)" do
    before { stub_sts }

    it "builds the STS client with credentials:false (the token carries the auth)" do
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Aws::STS::Client).to have_received(:new).with(hash_including(credentials: false))
    end

    it "supplies a default region when none is configured" do
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Aws::STS::Client).to have_received(:new).with(hash_including(region: "us-east-1"))
    end

    it "honors a configured region for the STS client" do
      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("region" => "eu-west-1"))

      expect(Aws::STS::Client).to have_received(:new).with(hash_including(region: "eu-west-1"))
    end

    it "does NOT pass any :endpoint to Aws::STS::Client.new even when config carries one" do
      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("endpoint" => "http://169.254.169.254/"))

      expect(Aws::STS::Client).to have_received(:new) do |opts|
        expect(opts).not_to have_key(:endpoint)
        expect(opts).not_to have_key("endpoint")
      end
    end
  end

  # ==========================================================================
  # DurationSeconds clamp (inherited from AwsStsBroker)
  # ==========================================================================
  describe "duration clamp (inherited)" do
    it "clamps an over-range duration_seconds to the STS max (43200)" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: config.merge("duration_seconds" => 999_999))

      expect(client).to have_received(:assume_role_with_web_identity).with(
        hash_including(duration_seconds: 43_200)
      )
    end

    it "defaults to 3600 when duration_seconds is absent" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(client).to have_received(:assume_role_with_web_identity).with(
        hash_including(duration_seconds: 3600)
      )
    end
  end

  # ==========================================================================
  # token_url source — fetched through the SSRF-guarded connection ONLY
  # ==========================================================================
  describe "token sourced from token_url (SSRF-guarded)" do
    let(:token_url) { "https://idp.internal/token" }
    let(:url_config) { { "role_arn" => role_arn, "token_url" => token_url } }

    it "fetches the token through HttpConnectionFactory.build (the SSRF guard)" do
      stub_sts
      conn = stub_token_http

      broker.acquire(data_source: data_source, base_credential: base_credential, config: url_config)

      # The fetch MUST go through the guarded connection dispatched against the
      # ABSOLUTE token_url (so SsrfGuardMiddleware re-validates the exact target).
      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
      expect(conn).to have_received(:run_request).with(:get, token_url, nil, nil)
    end

    it "resolve-and-pins the token_url via validate_url! before dispatch" do
      stub_sts
      stub_token_http

      broker.acquire(data_source: data_source, base_credential: base_credential, config: url_config)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:validate_url!).with(token_url)
    end

    it "exchanges the fetched token body for an STS session" do
      client = stub_sts
      stub_token_http(response: http_response(status: 200, body: "remote.jwt.value"))

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: url_config)

      expect(result).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(client).to have_received(:assume_role_with_web_identity).with(
        hash_including(web_identity_token: "remote.jwt.value")
      )
    end

    it "honors a POST token_request_method for the token fetch" do
      stub_sts
      conn = stub_token_http

      broker.acquire(data_source: data_source, base_credential: base_credential,
                     config: url_config.merge("token_request_method" => "post"))

      expect(conn).to have_received(:run_request).with(:post, token_url, nil, nil)
    end

    it "degrades to base when the token endpoint returns a non-2xx (blank token)" do
      stub_sts
      stub_token_http(response: http_response(status: 500, body: "boom"))

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: url_config)

      # An unsuccessful fetch yields no token => no exchange => base unchanged.
      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end
  end

  # ==========================================================================
  # Degrade paths — misconfiguration returns base UNCHANGED, no STS call.
  # ==========================================================================
  describe "degrade on misconfiguration" do
    it "returns the base credential and never calls STS when role_arn is blank" do
      allow(Aws::STS::Client).to receive(:new)
      other_base = instance_double("Ai::DataSourceCredential",
                                   decrypted_api_key: "k", decrypted_api_secret: "s")

      result = broker.acquire(data_source: data_source, base_credential: other_base,
                              config: { "role_arn" => "", "web_identity_token" => web_identity_token })

      expect(result).to equal(other_base)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential and never calls STS when role_arn is missing entirely" do
      allow(Aws::STS::Client).to receive(:new)

      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "web_identity_token" => web_identity_token })

      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential and never calls STS when NO token source is configured" do
      allow(Aws::STS::Client).to receive(:new)

      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "role_arn" => role_arn })

      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end

    it "returns the base credential when the inline web_identity_token is blank" do
      allow(Aws::STS::Client).to receive(:new)

      result = broker.acquire(data_source: data_source, base_credential: base_credential,
                              config: { "role_arn" => role_arn, "web_identity_token" => "" })

      expect(result).to equal(base_credential)
      expect(Aws::STS::Client).not_to have_received(:new)
    end
  end

  # ==========================================================================
  # Fail-safe — any STS error degrades to the base credential (never raises).
  # ==========================================================================
  describe "STS error fail-safe" do
    it "returns the base credential unchanged when AssumeRoleWithWebIdentity raises" do
      stub_sts(error: StandardError.new("InvalidIdentityToken"))

      result = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(result).to equal(base_credential)
    end

    it "does not raise out of #acquire on an STS service error" do
      stub_sts(error: RuntimeError.new("ExpiredTokenException"))

      expect do
        broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      end.not_to raise_error
    end
  end

  # ==========================================================================
  # Cache reuse — a repeat call with the SAME token source hits the cache
  # (the cache key is independent of the volatile token VALUE).
  # ==========================================================================
  describe "cache reuse across identical token sources" do
    it "performs only ONE STS exchange across two inline-token calls (cache HIT)" do
      client = stub_sts

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)
      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(client).to have_received(:assume_role_with_web_identity).once
    end
  end
end

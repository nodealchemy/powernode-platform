# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::AtprotoAppPasswordBroker — exchanges a stored
# AT Protocol (Bluesky) handle + APP PASSWORD (read off the BASE credential's
# generic api_key/api_secret pair) for a SHORT-LIVED session accessJwt via
# com.atproto.server.createSession, just before the signed fetch. The returned
# BrokeredCredential's #decrypted_api_key IS the accessJwt, so the existing
# BearerSigner sends "Authorization: Bearer <accessJwt>" UNCHANGED.
#
# HERMETIC (mirrors oauth2_client_credentials_broker_spec.rb):
#   - The session POST goes through the SSRF-guarded #broker_http_connection ->
#     HttpConnectionFactory.validate_url! + HttpConnectionFactory.build(...). We
#     stub .build to hand back a Faraday connection double and .validate_url! to
#     a no-op — no socket is ever opened.
#   - The lease cache uses the REAL shared Redis client (Powernode::Redis.client,
#     available in test). Each example flushes the "ds_cred_broker:" namespace so
#     a cached session can never leak between examples.
RSpec.describe Ai::DataSources::Credentials::AtprotoAppPasswordBroker, type: :service do
  subject(:broker) { described_class.new }

  # The BASE credential carries the AT Proto login pair (NEVER config):
  #   decrypted_api_key    -> identifier (handle)
  #   decrypted_api_secret -> app password
  let(:base_credential) do
    instance_double("Ai::DataSources::CredentialView",
                    decrypted_api_key: "alice.bsky.social",
                    decrypted_api_secret: "app-pw-1234-abcd-5678-efgh")
  end

  let(:data_source) do
    instance_double("Ai::DataSource", id: "ds-atproto-1", slug: "bluesky_src",
                    api_base_url: "https://bsky.social")
  end

  let(:config) { { "type" => "atproto_app_password" } }

  # A real (unsigned "none"-alg) JWT carrying an "exp" claim ~1h out, so the
  # broker's exp-decode path has something genuine to parse.
  def access_jwt_with_exp(seconds_from_now)
    JWT.encode({ "exp" => seconds_from_now.from_now.to_i }, nil, "none")
  end

  let(:access_jwt) { access_jwt_with_exp(1.hour) }
  let(:session_body) do
    {
      "did" => "did:plc:abc123", "handle" => "alice.bsky.social",
      "accessJwt" => access_jwt, "refreshJwt" => "RJ-SECRET-DO-NOT-LOG"
    }.to_json
  end

  def http_response(status:, body: "")
    instance_double("Faraday::Response", status: status, body: body)
  end

  def stub_session(response: nil)
    response ||= http_response(status: 200, body: session_body)
    conn = instance_double("Faraday::Connection")
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
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

  before { flush_broker_cache! }
  after { flush_broker_cache! }

  # ==========================================================================
  # Happy path — acquire returns a bearer BrokeredCredential
  # ==========================================================================
  describe "#acquire happy path" do
    it "returns a BrokeredCredential whose #decrypted_api_key is the accessJwt" do
      stub_session

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(cred.decrypted_api_key).to eq(access_jwt)
      expect(cred.decrypted_api_secret).to be_nil
    end

    it "sets a lease expiry from the accessJwt's own exp claim" do
      stub_session

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.expires_at).to be_a(Time)
      expect(cred.expires_at).to be > Time.current
      expect(cred.expired?).to be(false)
    end

    it "POSTs com.atproto.server.createSession with the identifier/password JSON body" do
      conn = stub_session

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("https://bsky.social/xrpc/com.atproto.server.createSession")
        parsed = JSON.parse(body)
        expect(parsed["identifier"]).to eq("alice.bsky.social")
        expect(parsed["password"]).to eq("app-pw-1234-abcd-5678-efgh")
        expect(headers["Content-Type"]).to eq("application/json")
      end
    end

    it "tolerates a Hash session body (already-parsed JSON) and still extracts the accessJwt" do
      stub_session(response: http_response(status: 200, body: { "accessJwt" => access_jwt, "refreshJwt" => "RJ" }))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.decrypted_api_key).to eq(access_jwt)
    end
  end

  # ==========================================================================
  # exp-claim decoding — fallback + clamp
  # ==========================================================================
  describe "exp-claim lease derivation" do
    it "falls back to DEFAULT_SESSION_TTL_SECONDS when the accessJwt has no exp claim" do
      no_exp_jwt = JWT.encode({ "sub" => "alice" }, nil, "none")
      stub_session(response: http_response(status: 200, body: { "accessJwt" => no_exp_jwt }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.expires_at).to be_within(5).of(Time.current + described_class::DEFAULT_SESSION_TTL_SECONDS)
    end

    it "falls back to DEFAULT_SESSION_TTL_SECONDS when the accessJwt is not a well-formed JWT" do
      stub_session(response: http_response(status: 200, body: { "accessJwt" => "not-a-jwt" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.decrypted_api_key).to eq("not-a-jwt")
      expect(cred.expires_at).to be_within(5).of(Time.current + described_class::DEFAULT_SESSION_TTL_SECONDS)
    end

    it "clamps an implausible exp so the cached lease never exceeds MAX_SESSION_TTL_SECONDS" do
      far_future_jwt = access_jwt_with_exp(365.days)
      stub_session(response: http_response(status: 200, body: { "accessJwt" => far_future_jwt }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.expires_at).to be <= (Time.current + described_class::MAX_SESSION_TTL_SECONDS + 5)
    end
  end

  # ==========================================================================
  # max_redirects: 0 — a login endpoint must not redirect
  # ==========================================================================
  describe "redirect hardening" do
    it "forwards max_redirects: 0 to HttpConnectionFactory.build" do
      stub_session

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
        .with(hash_including(max_redirects: 0))
    end
  end

  # ==========================================================================
  # DEGRADE — fail-safe to the base credential, never crash
  # ==========================================================================
  describe "#acquire degrade paths (return base credential unchanged)" do
    it "returns the base credential WITHOUT any HTTP when the identifier is blank" do
      blank_id = instance_double("Ai::DataSources::CredentialView",
                                 decrypted_api_key: "", decrypted_api_secret: "app-pw")
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: blank_id, config: config)

      expect(cred).to be(blank_id)
    end

    it "returns the base credential WITHOUT any HTTP when the app password is blank" do
      blank_secret = instance_double("Ai::DataSources::CredentialView",
                                     decrypted_api_key: "alice.bsky.social", decrypted_api_secret: "")
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: blank_secret, config: config)

      expect(cred).to be(blank_secret)
    end

    it "returns the base credential WITHOUT any HTTP when the data source has no api_base_url" do
      hostless_source = instance_double("Ai::DataSource", id: "ds-atproto-2", slug: "bluesky_src", api_base_url: "")
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: hostless_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "returns the base credential on a non-2xx session response (no session minted)" do
      stub_session(response: http_response(status: 401, body: { "error" => "AuthenticationRequired" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "returns the base credential on a 2xx body that carries no accessJwt" do
      stub_session(response: http_response(status: 200, body: { "did" => "did:plc:abc" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "returns the base credential on a 2xx body that is not JSON" do
      stub_session(response: http_response(status: 200, body: "<html>not json</html>"))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "FAILS SAFE to the base credential when the session URL is rejected as an SSRF target" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "FAILS SAFE to the base credential on a transport error during the session POST" do
      conn = instance_double("Faraday::Connection")
      allow(conn).to receive(:run_request).and_raise(Faraday::TimeoutError.new("execution expired"))
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end
  end

  # ==========================================================================
  # SECURITY — the app password / accessJwt / refreshJwt are NEVER logged
  # ==========================================================================
  describe "secret hygiene" do
    it "never writes the app password, accessJwt, or refreshJwt to the Rails log" do
      secret_jwt = access_jwt_with_exp(1.hour)
      stub_session(response: http_response(
        status: 200, body: { "accessJwt" => secret_jwt, "refreshJwt" => "REFRESH-DEADBEEF-LEAK" }.to_json
      ))

      logged = []
      %i[debug info warn error].each do |level|
        allow(Rails.logger).to receive(level) { |msg| logged << msg.to_s }
      end

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      joined = logged.join("\n")
      expect(joined).not_to include(secret_jwt)
      expect(joined).not_to include("app-pw-1234-abcd-5678-efgh")
      expect(joined).not_to include("REFRESH-DEADBEEF-LEAK")
    end

    it "never surfaces the app password in the error audit line on a transport failure" do
      conn = instance_double("Faraday::Connection")
      allow(conn).to receive(:run_request).and_raise(StandardError.new("boom app-pw-1234-abcd-5678-efgh"))
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      joined = logged.join("\n")
      expect(joined).not_to include("app-pw-1234-abcd-5678-efgh")
      expect(joined).not_to include("boom")
    end
  end

  # ==========================================================================
  # broker_type registry token
  # ==========================================================================
  describe "#broker_type" do
    it "reports the canonical registry token" do
      expect(broker.send(:broker_type)).to eq("atproto_app_password")
    end
  end
end

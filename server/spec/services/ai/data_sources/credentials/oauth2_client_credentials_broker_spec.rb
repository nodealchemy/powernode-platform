# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::Oauth2ClientCredentialsBroker — exchanges a
# stored OAuth2 CLIENT (client_id + client_secret, read off the BASE credential)
# for a SHORT-LIVED bearer access_token via the RFC 6749 `client_credentials`
# grant, just before the signed fetch. The returned BrokeredCredential's
# #decrypted_api_key IS the access_token, so the existing BearerSigner sends
# "Authorization: Bearer <token>" UNCHANGED.
#
# HERMETIC:
#   - The token POST goes through the SSRF-guarded
#     #broker_http_connection -> HttpConnectionFactory.validate_url! +
#     HttpConnectionFactory.build(...). We stub .build to hand back a Faraday
#     connection double whose #run_request returns a response double, and stub
#     .validate_url! to a no-op (SSRF is covered in the factory's own spec) —
#     so no socket is ever opened. (Mirrors query_service_spec / robots_service_spec.)
#   - The lease cache uses the REAL shared Redis client (Powernode::Redis.client,
#     available in test). Each example flushes the "ds_cred_broker:" namespace in
#     a before/after hook so a cached token can never leak between examples.
RSpec.describe Ai::DataSources::Credentials::Oauth2ClientCredentialsBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:token_url) { "https://idp.example.com/token" }

  # The BASE credential carries the OAuth CLIENT secret pair (NEVER config):
  #   decrypted_api_key    -> client_id
  #   decrypted_api_secret -> client_secret
  let(:base_credential) do
    instance_double("Ai::DataSources::CredentialView",
                    decrypted_api_key: "client-id",
                    decrypted_api_secret: "client-secret")
  end

  # A DataSource stand-in: only #id (cache key) and #slug (audit line) are read.
  let(:data_source) { instance_double("Ai::DataSource", id: "ds-oauth-1", slug: "oauth_src") }

  let(:config) do
    {
      "type" => "oauth2_client_credentials",
      "token_url" => token_url,
      "scope" => "read"
    }
  end

  # The token endpoint's JSON body. expires_in 3600 => a ~1h lease.
  let(:token_body) { { "access_token" => "AT", "expires_in" => 3600 }.to_json }

  # A Faraday-response stand-in: only #status and #body are consulted by the impl.
  def http_response(status:, body: "")
    instance_double("Faraday::Response", status: status, body: body)
  end

  # Wire the SSRF-guarded connection so no socket opens. Returns the Faraday
  # connection double so callers can inspect the args #run_request was called with
  # (form body + headers). validate_url! is neutralised (the broker calls it for
  # the resolve-and-pin fail-fast before build); SSRF rejection is exercised in a
  # dedicated example by overriding validate_url!/build to raise.
  def stub_token_exchange(response: nil)
    response ||= http_response(status: 200, body: token_body)
    conn = instance_double("Faraday::Connection")
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    conn
  end

  # The brokered-credential cache is shared (real Redis); scrub the namespace so a
  # cached lease from one example can never satisfy the next.
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
    it "returns a BrokeredCredential whose #decrypted_api_key is the access_token" do
      stub_token_exchange

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(cred.decrypted_api_key).to eq("AT")
      # Token-only bearer scheme: no secret half.
      expect(cred.decrypted_api_secret).to be_nil
    end

    it "sets a lease expiry from expires_in so the bearer is not treated as eternal" do
      stub_token_exchange

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.expires_at).to be_a(Time)
      expect(cred.expires_at).to be > Time.current
      expect(cred.expired?).to be(false)
    end

    it "POSTs the token endpoint with grant_type=client_credentials and the scope in the body" do
      conn = stub_token_exchange

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(conn).to have_received(:run_request) do |method, url, body, _headers|
        expect(method).to eq(:post)
        expect(url).to eq(token_url)
        form = URI.decode_www_form(body.to_s).to_h
        expect(form["grant_type"]).to eq("client_credentials")
        expect(form["scope"]).to eq("read")
      end
    end

    it "tolerates a Hash token body (already-parsed JSON) and still extracts the token" do
      stub_token_exchange(response: http_response(status: 200, body: { "access_token" => "AT", "expires_in" => 3600 }))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(cred.decrypted_api_key).to eq("AT")
    end
  end

  # ==========================================================================
  # client_auth — "basic" (default) vs "body"
  # ==========================================================================
  describe "client_auth selection" do
    # Capture the (body, headers) the broker handed run_request so we can assert
    # WHERE the client_id/client_secret travelled.
    def captured_request(conn)
      args = {}
      expect(conn).to have_received(:run_request) do |_method, _url, body, headers|
        args[:form] = URI.decode_www_form(body.to_s).to_h
        args[:headers] = headers
      end
      args
    end

    it "sends HTTP Basic Authorization base64(id:secret) by default and NOT credentials in the body" do
      conn = stub_token_exchange

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      req = captured_request(conn)
      expected = "Basic #{Base64.strict_encode64('client-id:client-secret')}"
      expect(req[:headers]["Authorization"]).to eq(expected)
      # In basic mode the client credentials never appear in the form body.
      expect(req[:form]).not_to have_key("client_id")
      expect(req[:form]).not_to have_key("client_secret")
    end

    it "treats an explicit client_auth 'basic' identically to the default" do
      conn = stub_token_exchange

      broker.acquire(
        data_source: data_source, base_credential: base_credential,
        config: config.merge("client_auth" => "basic")
      )

      req = captured_request(conn)
      expect(req[:headers]["Authorization"]).to eq("Basic #{Base64.strict_encode64('client-id:client-secret')}")
    end

    it "puts client_id/client_secret in the form body and sends NO Basic header when client_auth is 'body'" do
      conn = stub_token_exchange

      broker.acquire(
        data_source: data_source, base_credential: base_credential,
        config: config.merge("client_auth" => "body")
      )

      req = captured_request(conn)
      expect(req[:form]["client_id"]).to eq("client-id")
      expect(req[:form]["client_secret"]).to eq("client-secret")
      expect(req[:headers]).not_to have_key("Authorization")
    end
  end

  # ==========================================================================
  # max_redirects: 0 — a token endpoint must not redirect
  # ==========================================================================
  describe "redirect hardening" do
    it "forwards max_redirects: 0 to HttpConnectionFactory.build" do
      conn = stub_token_exchange

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(Ai::DataSources::HttpConnectionFactory).to have_received(:build)
        .with(hash_including(max_redirects: 0))
    end
  end

  # ==========================================================================
  # expires_in clamp — an absurd lease must not pin a stale bearer for years
  # ==========================================================================
  describe "expires_in clamp (MAX_TOKEN_TTL_SECONDS)" do
    it "caps an absurd expires_in so the cached lease TTL never exceeds the daily ceiling" do
      stub_token_exchange(
        response: http_response(status: 200, body: { "access_token" => "AT", "expires_in" => 999_999_999 }.to_json)
      )

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      # Inspect the REAL Redis TTL on the namespaced lease key: it must be clamped
      # to <= MAX_TOKEN_TTL_SECONDS (86_400), NOT the ~10^9 the endpoint claimed.
      cached_keys = Powernode::Redis.client.keys(
        "#{Ai::DataSources::Credentials::BrokerCache::NAMESPACE}oauth2:*"
      ).reject { |k| k.include?("lock:") }
      expect(cached_keys).not_to be_empty

      ttl = Powernode::Redis.client.ttl(cached_keys.first)
      expect(ttl).to be > 0
      expect(ttl).to be <= described_class::MAX_TOKEN_TTL_SECONDS
      expect(ttl).to be <= 86_400
    end

    it "clamps the returned credential's own expiry to within the daily ceiling" do
      stub_token_exchange(
        response: http_response(status: 200, body: { "access_token" => "AT", "expires_in" => 999_999_999 }.to_json)
      )

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred.expires_at).to be <= (Time.current + described_class::MAX_TOKEN_TTL_SECONDS + 5)
    end
  end

  # ==========================================================================
  # DEGRADE — fail-safe to the base credential, never crash
  # ==========================================================================
  describe "#acquire degrade paths (return base credential unchanged)" do
    it "returns the base credential WITHOUT any HTTP when token_url is blank" do
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(
        data_source: data_source, base_credential: base_credential,
        config: config.merge("token_url" => "")
      )

      expect(cred).to be(base_credential)
    end

    it "returns the base credential WITHOUT any HTTP when the client_id is blank" do
      blank_id = instance_double("Ai::DataSources::CredentialView",
                                 decrypted_api_key: "",
                                 decrypted_api_secret: "client-secret")
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: blank_id, config: config)

      expect(cred).to be(blank_id)
    end

    it "returns the base credential on a non-2xx token response (no bearer minted)" do
      stub_token_exchange(response: http_response(status: 401, body: { "error" => "invalid_client" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "returns the base credential on a 2xx body that carries no access_token" do
      stub_token_exchange(response: http_response(status: 200, body: { "token_type" => "bearer" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "returns the base credential on a 2xx body that is not JSON" do
      stub_token_exchange(response: http_response(status: 200, body: "<html>not json</html>"))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "FAILS SAFE to the base credential when the token_url is rejected as an SSRF target" do
      # The broker's broker_http_connection calls validate_url! FIRST (resolve-and-pin);
      # an SsrfError there (e.g. token_url -> 169.254.169.254) must degrade, not crash.
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "FAILS SAFE when HttpConnectionFactory.build itself raises an SsrfError" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end

    it "FAILS SAFE to the base credential on a transport error during the token POST" do
      conn = instance_double("Faraday::Connection")
      allow(conn).to receive(:run_request).and_raise(Faraday::TimeoutError.new("execution expired"))
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end
  end

  # ==========================================================================
  # SECURITY — the access_token / client_secret are NEVER logged
  # ==========================================================================
  describe "secret hygiene" do
    it "never writes the access_token or client_secret to the Rails log" do
      # Use DISTINCTIVE sentinels (a bare 2-char "AT" would false-positive on
      # incidental log substrings like "stATus"); these only ever appear if the
      # broker actually leaked the material.
      secret_token = "TOKEN-DEADBEEF-LEAK"
      stub_token_exchange(
        response: http_response(status: 200, body: { "access_token" => secret_token, "expires_in" => 3600 }.to_json)
      )

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:debug) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      joined = logged.join("\n")
      expect(joined).not_to include(secret_token)
      expect(joined).not_to include("client-secret")
    end

    it "never surfaces the secret in the error audit line on a transport failure" do
      conn = instance_double("Faraday::Connection")
      # An exception MESSAGE that would echo the secret if interpolated naively.
      allow(conn).to receive(:run_request).and_raise(StandardError.new("boom client-secret AT"))
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      # BaseBroker#acquire logs e.class only, never the message — so neither the
      # token nor the secret embedded in the exception message leaks.
      joined = logged.join("\n")
      expect(joined).not_to include("client-secret")
      expect(joined).not_to include("boom")
    end
  end

  # ==========================================================================
  # broker_type registry token
  # ==========================================================================
  describe "#broker_type" do
    it "reports the canonical registry token" do
      # broker_type is protected; send to read the canonical value.
      expect(broker.send(:broker_type)).to eq("oauth2_client_credentials")
    end
  end
end

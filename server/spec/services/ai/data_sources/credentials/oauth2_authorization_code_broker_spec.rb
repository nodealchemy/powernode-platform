# frozen_string_literal: true

require "rails_helper"

# Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker — I3's silent
# refresh of an OAuth2 Authorization-Code credential (I1 connect flow + I2
# storage). Unlike Oauth2ClientCredentialsBroker (which mints an EPHEMERAL,
# Redis-cached token from a static client_id/client_secret pair), this broker's
# BASE credential is a real Ai::DataSourceCredential ALREADY carrying a
# user-context access_token + refresh_token — the "cache" IS the credential
# row (access_token_expires_at), so a fresh token means NO network call at all.
#
# HERMETIC: the refresh POST goes through the SSRF-guarded
# #broker_http_connection -> HttpConnectionFactory.validate_url! + .build. We
# stub .build to hand back a Faraday connection double (mirrors
# oauth2_client_credentials_broker_spec) so no socket is ever opened, except in
# the dedicated SSRF example which lets the real guard reject a literal
# blocked address (no DNS round-trip needed, so it stays hermetic).
RSpec.describe Ai::DataSources::Credentials::Oauth2AuthorizationCodeBroker, type: :service do
  subject(:broker) { described_class.new }

  let(:token_url) { "https://api.x.example.com/2/oauth2/token" }
  let(:account) { create(:account) }
  let(:data_source) do
    create(:ai_data_source, account: account, auth_config: { "token_url" => token_url })
  end
  let(:config) { { "type" => "oauth2_authorization_code", "token_url" => token_url } }

  def http_response(status:, body: "")
    instance_double("Faraday::Response", status: status, body: body)
  end

  # Wire the SSRF-guarded connection so no socket opens. Returns the Faraday
  # connection double so callers can inspect the (body, headers) run_request
  # was called with. validate_url! is neutralised here; SSRF rejection is
  # exercised in a dedicated example by leaving it un-stubbed.
  def stub_token_exchange(response: nil)
    response ||= http_response(
      status: 200,
      body: { "access_token" => "AT-NEW", "refresh_token" => "RT-NEW", "expires_in" => 7200 }.to_json
    )
    conn = instance_double("Faraday::Connection")
    allow(conn).to receive(:run_request).and_return(response)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    conn
  end

  # ==========================================================================
  # Fresh token — NO network call
  # ==========================================================================
  describe "a fresh (non-expired) access token" do
    let(:credential) do
      create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-CURRENT", encrypted_refresh_token: "RT-CURRENT",
        access_token_expires_at: 1.hour.from_now)
    end

    it "is returned as-is with NO HTTP request made" do
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(cred).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(cred.decrypted_api_key).to eq("AT-CURRENT")
      expect(cred.expires_at).to be_within(1.second).of(credential.access_token_expires_at)
    end
  end

  # ==========================================================================
  # needs_refresh? — refresh POST, new token + expiry persisted
  # ==========================================================================
  describe "an expired / near-expiry access token" do
    let(:credential) do
      create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-CURRENT",
        access_token_expires_at: 5.seconds.ago)
    end

    it "POSTs the refresh_token grant and returns the new access_token" do
      stub_token_exchange

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(cred).to be_a(Ai::DataSources::Credentials::BrokeredCredential)
      expect(cred.decrypted_api_key).to eq("AT-NEW")
    end

    it "sends grant_type=refresh_token with the stored refresh_token and HTTP Basic client auth" do
      conn = stub_token_exchange

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq(token_url)
        form = URI.decode_www_form(body.to_s).to_h
        expect(form["grant_type"]).to eq("refresh_token")
        expect(form["refresh_token"]).to eq("RT-CURRENT")
        expect(headers["Authorization"]).to eq("Basic #{Base64.strict_encode64('client-id:client-secret')}")
      end
    end

    it "persists the new access_token and access_token_expires_at onto the credential" do
      stub_token_exchange

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      credential.reload
      expect(credential.decrypted_access_token).to eq("AT-NEW")
      expect(credential.access_token_expires_at).to be_within(5.seconds).of(7200.seconds.from_now)
    end

    it "does not refresh (no HTTP) when needs_refresh? is false" do
      credential.update!(access_token_expires_at: 1.hour.from_now)
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      broker.acquire(data_source: data_source, base_credential: credential, config: config)
    end

    context "a public client (no client_secret)" do
      let(:credential) do
        create(:ai_data_source_credential, data_source: data_source, account: account,
          client_id: "public-client-id", client_secret: nil,
          encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-CURRENT",
          access_token_expires_at: 5.seconds.ago)
      end

      it "identifies via client_id in the form body and sends no Authorization header" do
        conn = stub_token_exchange

        broker.acquire(data_source: data_source, base_credential: credential, config: config)

        expect(conn).to have_received(:run_request) do |_method, _url, body, headers|
          form = URI.decode_www_form(body.to_s).to_h
          expect(form["client_id"]).to eq("public-client-id")
          expect(headers).not_to have_key("Authorization")
        end
      end
    end
  end

  # ==========================================================================
  # refresh_token rotation — RFC 6749 sec. 6
  # ==========================================================================
  describe "refresh_token rotation" do
    let(:credential) do
      create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-OLD",
        access_token_expires_at: 5.seconds.ago)
    end

    it "persists a rotated refresh_token when the provider returns a new one" do
      stub_token_exchange(
        response: http_response(
          status: 200,
          body: { "access_token" => "AT-NEW", "refresh_token" => "RT-ROTATED", "expires_in" => 3600 }.to_json
        )
      )

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(credential.reload.decrypted_refresh_token).to eq("RT-ROTATED")
    end

    it "keeps the EXISTING refresh_token when the provider omits it" do
      stub_token_exchange(
        response: http_response(status: 200, body: { "access_token" => "AT-NEW", "expires_in" => 3600 }.to_json)
      )

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(credential.reload.decrypted_refresh_token).to eq("RT-OLD")
    end
  end

  # ==========================================================================
  # Refresh failure — secret-free error + record_failure!, no silent stale/blank
  # ==========================================================================
  describe "a refresh failure (non-2xx token response)" do
    let(:credential) do
      create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-SECRET-VALUE",
        access_token_expires_at: 5.seconds.ago)
    end

    it "degrades to the base credential (never crashes the fetch pipeline)" do
      stub_token_exchange(response: http_response(status: 400, body: { "error" => "invalid_grant" }.to_json))

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(cred).to be(credential)
    end

    it "records a persisted, operator-visible failure on the credential" do
      stub_token_exchange(response: http_response(status: 400, body: { "error" => "invalid_grant" }.to_json))

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      credential.reload
      expect(credential.consecutive_failures).to eq(1)
      expect(credential.last_test_status).to eq("failed")
      expect(credential.last_error).to be_present
    end

    it "does NOT rotate or blank out the stored access_token/refresh_token" do
      stub_token_exchange(response: http_response(status: 400, body: { "error" => "invalid_grant" }.to_json))

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      credential.reload
      expect(credential.decrypted_access_token).to eq("AT-STALE")
      expect(credential.decrypted_refresh_token).to eq("RT-SECRET-VALUE")
    end

    it "never leaks the refresh_token or client_secret in the Rails log or the persisted last_error" do
      stub_token_exchange(response: http_response(status: 400, body: { "error" => "invalid_grant" }.to_json))

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:debug) { |msg| logged << msg.to_s }

      broker.acquire(data_source: data_source, base_credential: credential, config: config)

      joined = logged.join("\n")
      expect(joined).not_to include("RT-SECRET-VALUE")
      expect(joined).not_to include("client-secret")
      expect(credential.reload.last_error.to_s).not_to include("RT-SECRET-VALUE")
      expect(credential.last_error.to_s).not_to include("client-secret")
    end
  end

  # ==========================================================================
  # SSRF — a rejected token_url degrades safely, same as the sibling broker
  # ==========================================================================
  describe "an SSRF-rejected token_url" do
    let(:credential) do
      create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-CURRENT",
        access_token_expires_at: 5.seconds.ago)
    end

    it "fails safe to the base credential when the token_url is rejected" do
      allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!)
        .and_raise(Ai::DataSources::HttpConnectionFactory::SsrfError.new("blocked host"))

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(cred).to be(credential)
      expect(credential.reload.decrypted_access_token).to eq("AT-STALE")
    end
  end

  # ==========================================================================
  # Degrade paths that need no HTTP at all
  # ==========================================================================
  describe "#acquire degrade paths (no refresh attempted)" do
    it "returns the base credential unchanged when it has no refresh_token" do
      credential = create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: nil, encrypted_refresh_token: nil,
        access_token_expires_at: nil)
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config)

      expect(cred).to be(credential)
    end

    it "returns the base credential unchanged when token_url is blank" do
      credential = create(:ai_data_source_credential, data_source: data_source, account: account,
        client_id: "client-id", client_secret: "client-secret",
        encrypted_access_token: "AT-STALE", encrypted_refresh_token: "RT-CURRENT",
        access_token_expires_at: 5.seconds.ago)
      expect(Ai::DataSources::HttpConnectionFactory).not_to receive(:build)

      cred = broker.acquire(data_source: data_source, base_credential: credential, config: config.merge("token_url" => ""))

      expect(cred).to be(credential)
    end

    it "returns the base credential unchanged when it does not respond to the OAuth2 token accessors" do
      base_credential = instance_double("Ai::DataSources::CredentialView", decrypted_api_key: "x")

      cred = broker.acquire(data_source: data_source, base_credential: base_credential, config: config)

      expect(cred).to be(base_credential)
    end
  end

  # ==========================================================================
  # broker_type registry token
  # ==========================================================================
  describe "#broker_type" do
    it "reports the canonical registry token" do
      expect(broker.send(:broker_type)).to eq("oauth2_authorization_code")
    end
  end
end

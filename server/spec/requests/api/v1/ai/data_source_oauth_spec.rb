# frozen_string_literal: true

require "rails_helper"

# x-com-provider campaign (I1): request-level coverage for the provider-agnostic
# OAuth 2.0 Authorization Code + PKCE connect flow served by
# Api::V1::Ai::DataSourceOauthController:
#
#   POST     /api/v1/ai/data_sources/:data_source_id/oauth/authorize  (JWT-authenticated)
#   GET|POST /api/v1/ai/data_sources/:data_source_id/oauth/callback   (UNAUTHENTICATED — state IS the auth model)
#
# HERMETIC: the token-exchange POST goes through the SSRF-guarded
# Ai::DataSources::HttpConnectionFactory. For every example EXCEPT the
# dedicated SSRF example, #validate_url! is stubbed to a no-op and #build
# returns a Faraday connection double (mirrors oauth2_client_credentials_broker_spec)
# so no socket is ever opened. The SSRF example deliberately does NOT stub
# either method — it points token_url at a literal blocked address so the REAL
# guard is exercised (a literal IP needs no DNS round-trip, so it stays hermetic).
RSpec.describe "Api::V1::Ai::DataSourceOauth", type: :request do
  let(:account)  { create(:account) }
  let(:operator) { user_with_permissions("ai.data_sources.update", account: account) }

  let!(:data_source) do
    create(:ai_data_source, account: account,
      auth_config: {
        "authorize_url" => "https://x.example.com/i/oauth2/authorize",
        "token_url" => "https://api.x.example.com/2/oauth2/token",
        "scopes" => %w[tweet.read tweet.write offline.access]
      })
  end
  let!(:credential) do
    create(:ai_data_source_credential, data_source: data_source, account: account,
      client_id: "x-com-client-id", client_secret: "x-com-client-secret")
  end

  let(:authorize_path) { "/api/v1/ai/data_sources/#{data_source.id}/oauth/authorize" }
  let(:callback_path)  { "/api/v1/ai/data_sources/#{data_source.id}/oauth/callback" }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
    SiteSetting.set("public_base_url", "https://app.example.com", setting_type: "string")
  end

  def perform_authorize!(user: operator)
    post authorize_path, headers: auth_headers_for(user), as: :json
    json_response_data
  end

  def stub_token_exchange(status: 200, body: nil)
    body ||= {
      "access_token" => "AT-12345",
      "refresh_token" => "RT-67890",
      "expires_in" => 7200,
      "scope" => "tweet.read tweet.write offline.access"
    }.to_json
    response_double = instance_double("Faraday::Response", status: status, body: body)
    conn = instance_double("Faraday::Connection")
    allow(conn).to receive(:run_request).and_return(response_double)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:validate_url!).and_return(true)
    allow(Ai::DataSources::HttpConnectionFactory).to receive(:build).and_return(conn)
    conn
  end

  # ==========================================================================
  # POST /oauth/authorize
  # ==========================================================================
  describe "POST /oauth/authorize" do
    it "requires JWT authentication" do
      post authorize_path, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it "requires ai.data_sources.update" do
      outsider = user_with_permissions("ai.data_sources.read", account: account)

      post authorize_path, headers: auth_headers_for(outsider), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "builds a correct authorization URL, persists state server-side, and never leaks the code_verifier" do
      data = perform_authorize!

      expect(data["authorization_url"]).to be_present
      expect(data["redirect_uri"]).to eq(
        "https://app.example.com/api/v1/ai/data_sources/#{data_source.id}/oauth/callback"
      )
      expect(data["state"]).to be_present

      uri = URI.parse(data["authorization_url"])
      query = URI.decode_www_form(uri.query.to_s).to_h
      expect(query["response_type"]).to eq("code")
      expect(query["client_id"]).to eq("x-com-client-id")
      expect(query["redirect_uri"]).to eq(data["redirect_uri"])
      expect(query["state"]).to eq(data["state"])
      expect(query["code_challenge_method"]).to eq("S256")
      expect(query["code_challenge"]).to be_present
      expect(query["scope"]).to eq("tweet.read tweet.write offline.access")

      # The code_verifier must NEVER be returned to the client — only the derived
      # S256 challenge travels in the URL. Confirm the raw response never carries it,
      # then confirm the server-side value it's actually checked against.
      pending_state = Rails.cache.read("ai:data_source_oauth:pending:#{data['state']}")
      expect(pending_state).to be_present
      expect(pending_state[:code_verifier]).to be_present
      expect(response.body).not_to include(pending_state[:code_verifier])
      expect(response.body).not_to include("code_verifier")

      expected_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(pending_state[:code_verifier]), padding: false)
      expect(query["code_challenge"]).to eq(expected_challenge)
    end

    it "returns 422 when auth_config is missing authorize_url/token_url" do
      data_source.update!(auth_config: {})

      post authorize_path, headers: auth_headers_for(operator), as: :json

      expect_error_response(nil, :unprocessable_content)
    end

    it "returns 422 when the data source has no credential with a client_id" do
      credential.update_columns(encrypted_client_id: nil)

      post authorize_path, headers: auth_headers_for(operator), as: :json

      expect_error_response(nil, :unprocessable_content)
    end
  end

  # ==========================================================================
  # GET|POST /oauth/callback — UNAUTHENTICATED (state is the auth model)
  #
  # All examples in THIS describe block pass `as: :json` to negotiate the raw
  # success/error envelope (the API-caller/test contract from I1). The
  # separate "browser redirect (I5)" describe block below covers the DEFAULT
  # (:html) format — what the provider's real top-level redirect negotiates —
  # which instead 302s to the frontend with an ?oauth=success|failed status.
  # ==========================================================================
  describe "GET|POST /oauth/callback" do
    it "rejects a missing state" do
      get callback_path, params: { code: "auth-code-123" }, as: :json

      expect_error_response("state", :unprocessable_content)
    end

    it "rejects an unknown state" do
      get callback_path, params: { state: "bogus-state-value", code: "auth-code-123" }, as: :json

      expect_error_response(nil, :unprocessable_content)
    end

    it "rejects an expired state" do
      auth = perform_authorize!

      travel 11.minutes do
        get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json
        expect_error_response(nil, :unprocessable_content)
      end
    end

    it "rejects when the provider reports an error (user denied consent)" do
      auth = perform_authorize!

      get callback_path, params: { state: auth["state"], error: "access_denied" }, as: :json

      expect_error_response("access_denied", :unprocessable_content)
    end

    it "rejects when the path's data_source_id does not match the state's — never trusts the path over the state" do
      other_source = create(:ai_data_source, account: account)
      auth = perform_authorize!

      get "/api/v1/ai/data_sources/#{other_source.id}/oauth/callback",
        params: { state: auth["state"], code: "auth-code-123" }, as: :json

      expect_error_response(nil, :unprocessable_content)
    end

    it "is single-use: a replayed callback with the same state is rejected the second time" do
      auth = perform_authorize!
      stub_token_exchange

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json
      expect_success_response

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json
      expect_error_response(nil, :unprocessable_content)
    end

    it "succeeds with NO Authorization header at all (this is the whole point of the flow)" do
      auth = perform_authorize!
      stub_token_exchange

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json

      expect_success_response
    end

    it "exchanges the code for tokens on the happy path and persists them onto the credential" do
      auth = perform_authorize!
      stub_token_exchange

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json

      expect_success_response
      expect(json_response_data["scopes"]).to eq(%w[tweet.read tweet.write offline.access])

      credential.reload
      expect(credential.decrypted_access_token).to eq("AT-12345")
      expect(credential.decrypted_refresh_token).to eq("RT-67890")
      expect(credential.access_token_expires_at).to be_within(5.seconds).of(7200.seconds.from_now)
      expect(credential.oauth_scopes).to eq(%w[tweet.read tweet.write offline.access])
      expect(credential.last_test_status).to eq("success")
    end

    it "POSTs the token endpoint with the PKCE code_verifier and NOT the client_secret in the form body" do
      auth = perform_authorize!
      conn = stub_token_exchange
      pending_state = Rails.cache.read("ai:data_source_oauth:pending:#{auth['state']}")

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json

      expect(conn).to have_received(:run_request) do |method, url, body, headers|
        expect(method).to eq(:post)
        expect(url).to eq("https://api.x.example.com/2/oauth2/token")
        form = URI.decode_www_form(body.to_s).to_h
        expect(form["grant_type"]).to eq("authorization_code")
        expect(form["code"]).to eq("auth-code-123")
        expect(form["code_verifier"]).to eq(pending_state[:code_verifier])
        expect(form["redirect_uri"]).to eq(pending_state[:redirect_uri])
        expect(form).not_to have_key("client_secret")
        expect(headers["Authorization"]).to eq("Basic #{Base64.strict_encode64('x-com-client-id:x-com-client-secret')}")
      end
    end

    it "marks the callback failed and records a credential failure on a non-2xx token response" do
      auth = perform_authorize!
      stub_token_exchange(status: 401, body: { error: "invalid_grant" }.to_json)

      get callback_path, params: { state: auth["state"], code: "bad-code" }, as: :json

      expect_error_response(nil, :unprocessable_content)
      expect(credential.reload.last_test_status).to eq("failed")
      expect(credential.decrypted_access_token).to be_nil
    end

    it "rejects a token_url that resolves to a disallowed (SSRF) address" do
      # A literal IP needs no DNS round-trip, so the REAL HttpConnectionFactory
      # guard runs hermetically here — this is the one example that does NOT
      # stub validate_url!/build.
      data_source.update!(auth_config: data_source.auth_config.merge("token_url" => "http://169.254.169.254/token"))
      auth = perform_authorize!

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json

      expect_error_response(nil, :unprocessable_content)
      expect(credential.reload.decrypted_access_token).to be_nil
    end

    it "never logs the access_token, refresh_token, or client_secret" do
      auth = perform_authorize!
      stub_token_exchange(body: {
        "access_token" => "TOKEN-LEAK-CHECK",
        "refresh_token" => "REFRESH-LEAK-CHECK",
        "expires_in" => 3600
      }.to_json)

      logged = []
      allow(Rails.logger).to receive(:info) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:warn) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:error) { |msg| logged << msg.to_s }
      allow(Rails.logger).to receive(:debug) { |msg| logged << msg.to_s }

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }, as: :json

      joined = logged.join("\n")
      expect(joined).not_to include("TOKEN-LEAK-CHECK")
      expect(joined).not_to include("REFRESH-LEAK-CHECK")
      expect(joined).not_to include("x-com-client-secret")
    end
  end

  # ==========================================================================
  # GET /oauth/callback — browser redirect (I5)
  #
  # The provider's real redirect is a top-level browser navigation, which
  # negotiates :html by default (no `as: :json`, no explicit Accept header —
  # matches an actual browser hitting this URL). That default format must land
  # the operator back in the frontend app instead of showing a raw JSON body.
  # ==========================================================================
  describe "GET /oauth/callback (default :html format)" do
    it "redirects to the frontend data-sources route with ?oauth=success and the data_source_id on success" do
      auth = perform_authorize!
      stub_token_exchange

      get callback_path, params: { state: auth["state"], code: "auth-code-123" }

      expect(response).to have_http_status(:found)
      location = URI.parse(response.headers["Location"])
      expect(location.path).to eq("/app/ai/infrastructure/data-sources")
      query = URI.decode_www_form(location.query.to_s).to_h
      expect(query["oauth"]).to eq("success")
      expect(query["data_source_id"]).to eq(data_source.id)
      expect(response.body).not_to include("AT-12345") # never leaks the token into the redirect
    end

    it "redirects with ?oauth=failed and an error message when the callback fails" do
      auth = perform_authorize!

      # The provider-error short-circuit fires before the state is even looked
      # up (see handle_callback), so no data_source_id is available here —
      # matches the existing JSON-contract test for this same case above,
      # which likewise never asserts a data_source_id.
      get callback_path, params: { state: auth["state"], error: "access_denied" }

      expect(response).to have_http_status(:found)
      location = URI.parse(response.headers["Location"])
      expect(location.path).to eq("/app/ai/infrastructure/data-sources")
      query = URI.decode_www_form(location.query.to_s).to_h
      expect(query["oauth"]).to eq("failed")
      expect(query["error"]).to include("access_denied")
    end

    it "redirects with ?oauth=failed and the data_source_id when the state resolved but the token exchange failed" do
      auth = perform_authorize!
      stub_token_exchange(status: 401, body: { error: "invalid_grant" }.to_json)

      get callback_path, params: { state: auth["state"], code: "bad-code" }

      expect(response).to have_http_status(:found)
      location = URI.parse(response.headers["Location"])
      query = URI.decode_www_form(location.query.to_s).to_h
      expect(query["oauth"]).to eq("failed")
      expect(query["data_source_id"]).to eq(data_source.id)
    end

    it "redirects with ?oauth=failed and no data_source_id when the state itself never resolved" do
      get callback_path, params: { state: "bogus-state-value", code: "auth-code-123" }

      expect(response).to have_http_status(:found)
      location = URI.parse(response.headers["Location"])
      query = URI.decode_www_form(location.query.to_s).to_h
      expect(query["oauth"]).to eq("failed")
      expect(query).not_to have_key("data_source_id")
    end
  end
end

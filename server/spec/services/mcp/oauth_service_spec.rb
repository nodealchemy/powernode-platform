# frozen_string_literal: true

require "rails_helper"

# Behavioral coverage for the real OAuth 2.1 + PKCE logic. The request spec
# (spec/requests/api/v1/mcp_oauth_spec.rb) fully stubs this service, so these
# examples are the only ones that execute the security-critical paths.
RSpec.describe Mcp::OauthService do
  let(:account) { create(:account) }
  let(:server) { create(:mcp_server, :oauth2, account: account) }
  let(:service) { described_class.new(server) }
  let(:token_url) { "https://oauth.example.com/token" }
  let(:redirect_uri) { "https://app.example.com/oauth/callback" }

  describe "#generate_pkce_challenge" do
    it "derives the challenge as unpadded urlsafe base64 of SHA256(verifier) (S256)" do
      pkce = service.generate_pkce_challenge

      expected = Base64.urlsafe_encode64(Digest::SHA256.digest(pkce[:code_verifier]), padding: false)
      expect(pkce[:code_challenge]).to eq(expected)
      expect(pkce[:code_challenge]).not_to end_with("=")
    end

    it "generates a high-entropy verifier, unique per call" do
      first = service.generate_pkce_challenge
      second = service.generate_pkce_challenge

      expect(first[:code_verifier].length).to be >= 43 # RFC 7636 minimum
      expect(first[:code_verifier]).not_to eq(second[:code_verifier])
    end
  end

  describe "#generate_authorization_url" do
    # Model validations normally require these fields on oauth2 servers;
    # bypass them (update_columns) to simulate legacy/corrupted rows — the
    # exact state validate_oauth_configuration! defends against.
    it "raises ConfigurationError when the client id is missing" do
      server.update_columns(oauth_client_id: nil)

      expect { service.generate_authorization_url(redirect_uri: redirect_uri) }
        .to raise_error(described_class::ConfigurationError, /client ID/i)
    end

    it "raises ConfigurationError when the authorization URL is missing" do
      server.update_columns(oauth_authorization_url: nil)

      expect { service.generate_authorization_url(redirect_uri: redirect_uri) }
        .to raise_error(described_class::ConfigurationError, /authorization URL/i)
    end

    it "raises ConfigurationError when the token URL is missing" do
      server.update_columns(oauth_token_url: nil)

      expect { service.generate_authorization_url(redirect_uri: redirect_uri) }
        .to raise_error(described_class::ConfigurationError, /token URL/i)
    end

    it "persists the CSRF state and PKCE verifier for callback validation and clears stale errors" do
      server.update!(oauth_error: "previous failure")

      url = service.generate_authorization_url(redirect_uri: redirect_uri)
      server.reload

      expect(server.oauth_state).to be_present
      expect(server.oauth_pkce_code_verifier).to be_present
      expect(server.oauth_error).to be_nil
      expect(url).to include("state=#{server.oauth_state}")
    end

    it "builds an S256 authorization URL whose challenge matches the persisted verifier" do
      url = service.generate_authorization_url(redirect_uri: redirect_uri)
      params = Rack::Utils.parse_query(URI.parse(url).query)
      server.reload

      expect(url).to start_with("https://oauth.example.com/authorize?")
      expect(params["response_type"]).to eq("code")
      expect(params["client_id"]).to eq(server.oauth_client_id)
      expect(params["redirect_uri"]).to eq(redirect_uri)
      expect(params["code_challenge_method"]).to eq("S256")
      expect(params["code_challenge"]).to eq(
        Base64.urlsafe_encode64(Digest::SHA256.digest(server.oauth_pkce_code_verifier), padding: false)
      )
    end
  end

  describe "#exchange_code_for_tokens" do
    before do
      server.update!(oauth_state: "expected-state", oauth_pkce_code_verifier: "the-verifier")
    end

    context "CSRF protection" do
      it "raises AuthorizationError on a state mismatch without contacting the token endpoint" do
        expect do
          service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "attacker-state")
        end.to raise_error(described_class::AuthorizationError, /state parameter/i)

        expect(WebMock).not_to have_requested(:post, token_url)
      end
    end

    context "with a successful token response" do
      let!(:token_stub) do
        stub_request(:post, token_url).to_return(
          status: 200,
          body: {
            access_token: "new-access-token",
            refresh_token: "new-refresh-token",
            expires_in: 3600,
            token_type: "Bearer"
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "sends the authorization code with the stored PKCE verifier" do
        service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")

        expect(WebMock).to have_requested(:post, token_url).with { |req|
          body = Rack::Utils.parse_query(req.body)
          body["grant_type"] == "authorization_code" &&
            body["code"] == "auth-code" &&
            body["code_verifier"] == "the-verifier" &&
            body["client_id"] == server.oauth_client_id &&
            !body.key?("client_secret")
        }
      end

      it "includes the client secret when one is configured" do
        server.update!(oauth_client_secret: "s3cret")

        service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")

        expect(WebMock).to have_requested(:post, token_url).with { |req|
          Rack::Utils.parse_query(req.body)["client_secret"] == "s3cret"
        }
      end

      it "stores the tokens and clears the one-time state and verifier" do
        service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")
        server.reload

        expect(server.oauth_access_token).to eq("new-access-token")
        expect(server.oauth_refresh_token).to eq("new-refresh-token")
        expect(server.oauth_token_type).to eq("Bearer")
        expect(server.oauth_token_expires_at).to be_within(1.minute).of(1.hour.from_now)
        expect(server.oauth_state).to be_nil
        expect(server.oauth_pkce_code_verifier).to be_nil
        expect(server.oauth_error).to be_nil
      end

      it "encrypts tokens at rest (never stores the raw value)" do
        service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")
        server.reload

        expect(server.oauth_access_token_encrypted).to be_present
        expect(server.oauth_access_token_encrypted).not_to include("new-access-token")
      end
    end

    context "when the provider rejects the exchange" do
      before do
        stub_request(:post, token_url).to_return(
          status: 400,
          body: { error: "invalid_grant", error_description: "Code expired" }.to_json
        )
      end

      it "raises OAuthError with the provider's error description and records it on the server" do
        expect do
          service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")
        end.to raise_error(described_class::OAuthError, /Code expired/)

        expect(server.reload.oauth_error).to include("Code expired")
      end
    end

    context "when the provider returns malformed JSON" do
      before { stub_request(:post, token_url).to_return(status: 200, body: "<html>not json</html>") }

      it "raises OAuthError" do
        expect do
          service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")
        end.to raise_error(described_class::OAuthError, /Invalid OAuth response/)
      end
    end

    context "when the token endpoint times out" do
      before { stub_request(:post, token_url).to_timeout }

      it "raises OAuthError" do
        expect do
          service.exchange_code_for_tokens(code: "auth-code", redirect_uri: redirect_uri, state: "expected-state")
        end.to raise_error(described_class::OAuthError, /timed out|Token exchange failed/)
      end
    end
  end

  describe "#refresh_token!" do
    it "raises TokenRefreshError when no refresh token is stored" do
      expect { service.refresh_token! }
        .to raise_error(described_class::TokenRefreshError, /No refresh token available/)

      expect(WebMock).not_to have_requested(:post, token_url)
    end

    context "with a stored refresh token" do
      before do
        server.update!(
          oauth_access_token: "old-access",
          oauth_refresh_token: "stored-refresh",
          oauth_token_expires_at: 1.minute.from_now
        )
      end

      it "posts a refresh_token grant and stores the rotated tokens" do
        stub_request(:post, token_url).to_return(
          status: 200,
          body: { access_token: "rotated-access", refresh_token: "rotated-refresh", expires_in: 7200 }.to_json
        )

        service.refresh_token!
        server.reload

        expect(WebMock).to have_requested(:post, token_url).with { |req|
          body = Rack::Utils.parse_query(req.body)
          body["grant_type"] == "refresh_token" && body["refresh_token"] == "stored-refresh"
        }
        expect(server.oauth_access_token).to eq("rotated-access")
        expect(server.oauth_refresh_token).to eq("rotated-refresh")
        expect(server.oauth_last_refreshed_at).to be_present
      end

      it "keeps the existing refresh token when the provider does not rotate it" do
        stub_request(:post, token_url).to_return(
          status: 200,
          body: { access_token: "rotated-access", expires_in: 7200 }.to_json
        )

        service.refresh_token!

        expect(server.reload.oauth_refresh_token).to eq("stored-refresh")
      end

      it "raises TokenRefreshError and records the failure when the provider rejects the refresh" do
        stub_request(:post, token_url).to_return(
          status: 401,
          body: { error: "invalid_grant" }.to_json
        )

        expect { service.refresh_token! }
          .to raise_error(described_class::TokenRefreshError, /invalid_grant/)

        expect(server.reload.oauth_error).to include("Token refresh failed")
      end
    end
  end

  describe "#get_valid_access_token" do
    it "returns the current token without any HTTP call when it is not expiring soon" do
      server.update!(oauth_access_token: "live-token", oauth_token_expires_at: 1.hour.from_now)

      expect(service.get_valid_access_token).to eq("live-token")
      expect(WebMock).not_to have_requested(:post, token_url)
    end

    it "auto-refreshes and returns the new token when the current one is expiring soon" do
      server.update!(
        oauth_access_token: "stale-token",
        oauth_refresh_token: "stored-refresh",
        oauth_token_expires_at: 1.minute.from_now
      )
      stub_request(:post, token_url).to_return(
        status: 200,
        body: { access_token: "fresh-token", expires_in: 3600 }.to_json
      )

      expect(service.get_valid_access_token).to eq("fresh-token")
    end

    it "raises TokenRefreshError when expiring with no refresh token available" do
      server.update!(oauth_access_token: "stale-token", oauth_token_expires_at: 1.minute.from_now)

      expect { service.get_valid_access_token }
        .to raise_error(described_class::TokenRefreshError, /no refresh token/i)
    end
  end

  describe "#revoke_tokens!" do
    it "clears all OAuth material from the server" do
      server.update!(
        oauth_access_token: "live-token",
        oauth_refresh_token: "stored-refresh",
        oauth_token_expires_at: 1.hour.from_now,
        oauth_state: "pending-state",
        oauth_pkce_code_verifier: "pending-verifier"
      )

      service.revoke_tokens!
      server.reload

      expect(server.oauth_access_token).to be_nil
      expect(server.oauth_refresh_token).to be_nil
      expect(server.oauth_token_expires_at).to be_nil
      expect(server.oauth_state).to be_nil
      expect(server.oauth_pkce_code_verifier).to be_nil
      expect(server.oauth_connected?).to be(false)
    end
  end
end

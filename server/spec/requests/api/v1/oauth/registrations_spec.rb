# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth Dynamic Client Registration", type: :request do
  let(:registration_endpoint) { "/api/v1/oauth/register" }

  describe "POST /api/v1/oauth/register" do
    context "with valid loopback redirect URI" do
      let(:valid_params) do
        {
          client_name: "Claude Code",
          redirect_uris: ["http://127.0.0.1:3456/callback"]
        }
      end

      it "returns 201 Created" do
        post registration_endpoint, params: valid_params, as: :json

        expect(response).to have_http_status(:created)
      end

      it "creates an OauthApplication" do
        expect {
          post registration_endpoint, params: valid_params, as: :json
        }.to change(OauthApplication, :count).by(1)
      end

      it "returns client_id" do
        post registration_endpoint, params: valid_params, as: :json

        body = JSON.parse(response.body)
        expect(body["client_id"]).to be_present
      end

      it "does not return client_secret" do
        post registration_endpoint, params: valid_params, as: :json

        body = JSON.parse(response.body)
        expect(body).not_to have_key("client_secret")
      end

      it "returns client_name matching request" do
        post registration_endpoint, params: valid_params, as: :json

        body = JSON.parse(response.body)
        expect(body["client_name"]).to eq("Claude Code")
      end

      it "returns grant_types" do
        post registration_endpoint, params: valid_params, as: :json

        body = JSON.parse(response.body)
        expect(body["grant_types"]).to contain_exactly("authorization_code", "refresh_token")
      end

      it "returns token_endpoint_auth_method as 'none'" do
        post registration_endpoint, params: valid_params, as: :json

        body = JSON.parse(response.body)
        expect(body["token_endpoint_auth_method"]).to eq("none")
      end

      it "creates application as non-confidential (public client)" do
        post registration_endpoint, params: valid_params, as: :json

        app = OauthApplication.last
        expect(app.confidential).to be false
      end

      it "stores registration metadata" do
        post registration_endpoint, params: valid_params, as: :json

        app = OauthApplication.last
        expect(app.metadata["registered_via"]).to eq("mcp_dynamic_registration")
      end

      it "does not require authentication" do
        # No auth headers provided — should still work
        post registration_endpoint, params: valid_params, as: :json
        expect(response).to have_http_status(:created)
      end
    end

    context "with localhost redirect URI" do
      it "accepts localhost" do
        post registration_endpoint, params: {
          client_name: "Test",
          redirect_uris: ["http://localhost:8080/callback"]
        }, as: :json

        expect(response).to have_http_status(:created)
      end

      it "accepts IPv6 loopback" do
        post registration_endpoint, params: {
          client_name: "Test",
          redirect_uris: ["http://[::1]:8080/callback"]
        }, as: :json

        expect(response).to have_http_status(:created)
      end
    end

    context "with non-loopback redirect URI" do
      it "rejects external redirect URIs" do
        post registration_endpoint, params: {
          client_name: "Evil App",
          redirect_uris: ["https://evil.example.com/callback"]
        }, as: :json

        expect(response).to have_http_status(:bad_request)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("invalid_redirect_uri")
      end
    end

    context "with restricted scopes" do
      it "filters out admin scope" do
        post registration_endpoint, params: {
          client_name: "Test",
          redirect_uris: ["http://127.0.0.1:3456/callback"],
          scope: "read write admin billing"
        }, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        scopes = body["scope"].split(" ")
        expect(scopes).to include("read", "write")
        expect(scopes).not_to include("admin", "billing")
      end

      it "rejects when all requested scopes are disallowed" do
        post registration_endpoint, params: {
          client_name: "Test",
          redirect_uris: ["http://127.0.0.1:3456/callback"],
          scope: "admin billing"
        }, as: :json

        expect(response).to have_http_status(:bad_request)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("invalid_scope")
      end
    end

    context "with missing redirect_uris" do
      it "returns 400" do
        post registration_endpoint, params: { client_name: "Test" }, as: :json

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "with default client name" do
      it "uses 'MCP Client' when client_name is omitted" do
        post registration_endpoint, params: {
          redirect_uris: ["http://127.0.0.1:3456/callback"]
        }, as: :json

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["client_name"]).to eq("MCP Client")
      end
    end
  end
end

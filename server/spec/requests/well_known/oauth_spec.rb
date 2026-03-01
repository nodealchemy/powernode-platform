# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Well-Known OAuth Discovery", type: :request do
  # ==========================================================================
  # RFC 9728 — OAuth Protected Resource Metadata
  # ==========================================================================
  describe "GET /.well-known/oauth-protected-resource" do
    before { get "/.well-known/oauth-protected-resource" }

    it "returns 200 OK" do
      expect(response).to have_http_status(:ok)
    end

    it "returns resource pointing to MCP endpoint" do
      body = JSON.parse(response.body)
      expect(body["resource"]).to end_with("/api/v1/mcp")
    end

    it "lists the authorization server" do
      body = JSON.parse(response.body)
      expect(body["authorization_servers"]).to be_an(Array)
      expect(body["authorization_servers"].length).to eq(1)
    end

    it "declares header as supported bearer method" do
      body = JSON.parse(response.body)
      expect(body["bearer_methods_supported"]).to eq(["header"])
    end

    it "lists supported scopes" do
      body = JSON.parse(response.body)
      expect(body["scopes_supported"]).to include("read", "write", "workflows", "files")
    end

    it "does not require authentication" do
      # Already called without auth headers — just verify it works
      expect(response).to have_http_status(:ok)
    end
  end

  # ==========================================================================
  # RFC 8414 — OAuth Authorization Server Metadata
  # ==========================================================================
  describe "GET /.well-known/oauth-authorization-server" do
    before { get "/.well-known/oauth-authorization-server" }

    it "returns 200 OK" do
      expect(response).to have_http_status(:ok)
    end

    it "includes issuer matching the base URL" do
      body = JSON.parse(response.body)
      expect(body["issuer"]).to be_present
      expect(body["issuer"]).not_to include("/api")
    end

    it "includes authorization_endpoint" do
      body = JSON.parse(response.body)
      expect(body["authorization_endpoint"]).to end_with("/api/v1/oauth/authorize")
    end

    it "includes token_endpoint" do
      body = JSON.parse(response.body)
      expect(body["token_endpoint"]).to end_with("/api/v1/oauth/token")
    end

    it "includes registration_endpoint" do
      body = JSON.parse(response.body)
      expect(body["registration_endpoint"]).to end_with("/api/v1/oauth/register")
    end

    it "includes revocation_endpoint" do
      body = JSON.parse(response.body)
      expect(body["revocation_endpoint"]).to end_with("/api/v1/oauth/revoke")
    end

    it "includes introspection_endpoint" do
      body = JSON.parse(response.body)
      expect(body["introspection_endpoint"]).to end_with("/api/v1/oauth/introspect")
    end

    it "supports only 'code' response type" do
      body = JSON.parse(response.body)
      expect(body["response_types_supported"]).to eq(["code"])
    end

    it "supports authorization_code and refresh_token grants" do
      body = JSON.parse(response.body)
      expect(body["grant_types_supported"]).to contain_exactly("authorization_code", "refresh_token")
    end

    it "declares 'none' as token endpoint auth method" do
      body = JSON.parse(response.body)
      expect(body["token_endpoint_auth_methods_supported"]).to eq(["none"])
    end

    it "requires S256 code challenge method" do
      body = JSON.parse(response.body)
      expect(body["code_challenge_methods_supported"]).to eq(["S256"])
    end

    it "lists supported scopes" do
      body = JSON.parse(response.body)
      expect(body["scopes_supported"]).to include("read", "write", "workflows", "files")
    end
  end
end

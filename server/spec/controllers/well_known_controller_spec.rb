# frozen_string_literal: true

require "rails_helper"

RSpec.describe WellKnownController, type: :controller do
  describe "GET #agent_card" do
    it "returns the platform agent card" do
      get :agent_card

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json["name"]).to eq("Powernode")
      expect(json["url"]).to include("/a2a")
      expect(json["version"]).to be_present
      expect(json["protocolVersion"]).to be_present
    end

    it "includes capabilities" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["capabilities"]).to include(
        "streaming" => true,
        "pushNotifications" => true
      )
    end

    it "includes authentication schemes" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["authentication"]["schemes"]).to include("bearer", "api_key")
    end

    it "includes skills" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["skills"]).to be_an(Array)
      expect(json["skills"].first).to include("id", "name", "description")
    end

    it "includes input/output modes" do
      get :agent_card

      json = JSON.parse(response.body)
      expect(json["defaultInputModes"]).to include("text/plain", "application/json")
      expect(json["defaultOutputModes"]).to include("text/plain", "application/json")
    end
  end

  describe "GET #oauth_protected_resource" do
    it "returns protected resource metadata" do
      get :oauth_protected_resource

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["resource"]).to include("/api/v1/mcp")
      expect(json["bearer_methods_supported"]).to include("header")
    end

    it "returns all 8 Doorkeeper scopes" do
      get :oauth_protected_resource

      json = JSON.parse(response.body)
      expected_scopes = %w[read write admin billing users webhooks workflows files]
      expect(json["scopes_supported"]).to match_array(expected_scopes)
    end
  end

  describe "GET #oauth_authorization_server" do
    it "returns authorization server metadata" do
      get :oauth_authorization_server

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["issuer"]).to be_present
      expect(json["authorization_endpoint"]).to include("/oauth/authorize")
      expect(json["token_endpoint"]).to include("/oauth/token")
      expect(json["code_challenge_methods_supported"]).to include("S256")
    end

    it "returns all 8 Doorkeeper scopes" do
      get :oauth_authorization_server

      json = JSON.parse(response.body)
      expected_scopes = %w[read write admin billing users webhooks workflows files]
      expect(json["scopes_supported"]).to match_array(expected_scopes)
    end

    it "scopes match between both OAuth discovery endpoints" do
      get :oauth_protected_resource
      pr_scopes = JSON.parse(response.body)["scopes_supported"]

      get :oauth_authorization_server
      as_scopes = JSON.parse(response.body)["scopes_supported"]

      expect(pr_scopes).to match_array(as_scopes)
    end
  end
end

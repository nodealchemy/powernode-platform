# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Tokens API", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", account: account) }
  let(:headers) { auth_headers_for(user) }

  # ===========================================================================
  # GET /api/v1/mcp/tokens
  # ===========================================================================
  describe "GET /api/v1/mcp/tokens" do
    let(:path) { "/api/v1/mcp/tokens" }

    it "returns list of user's MCP tokens" do
      # Create MCP tokens for the user
      UserToken.create_token_for_user(user, type: "mcp", name: "Token A")
      UserToken.create_token_for_user(user, type: "mcp", name: "Token B")

      get path, headers: headers

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(2)
      expect(data.first).to include("id", "name", "masked_token", "permissions", "expires_at")
    end

    it "returns empty array when no tokens exist" do
      get path, headers: headers

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data).to be_empty
    end

    it "only returns MCP type tokens, not access/refresh" do
      UserToken.create_token_for_user(user, type: "mcp", name: "MCP Token")
      UserToken.create_token_for_user(user, type: "access", name: "Access Token")

      get path, headers: headers

      expect_success_response
      data = json_response_data
      expect(data.length).to eq(1)
      expect(data.first["name"]).to eq("MCP Token")
    end

    it "requires ai.agents.read permission" do
      user_no_perm = user_with_permissions(account: account)
      get path, headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      get path, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # POST /api/v1/mcp/tokens
  # ===========================================================================
  describe "POST /api/v1/mcp/tokens" do
    let(:path) { "/api/v1/mcp/tokens" }

    it "creates MCP token with name" do
      post path, params: { name: "My MCP Token" }.to_json, headers: headers

      expect_success_response
      data = json_response_data
      expect(data["name"]).to eq("My MCP Token")
      expect(data["token_id"]).to be_present
    end

    it "returns raw token with pnmcp_ prefix (shown once)" do
      post path, params: { name: "Test Token" }.to_json, headers: headers

      expect_success_response
      data = json_response_data
      expect(data["token"]).to start_with("pnmcp_")
    end

    it "returns token_id, name, permissions, expires_at" do
      post path, params: { name: "Test Token" }.to_json, headers: headers

      expect_success_response
      data = json_response_data
      expect(data).to include("token_id", "name", "permissions", "expires_at", "created_at")
    end

    it "defaults permissions to user's permissions" do
      post path, params: { name: "Default Perms" }.to_json, headers: headers

      expect_success_response
      data = json_response_data
      expect(data["permissions"]).to include("ai.agents.read")
    end

    it "accepts custom permissions as a subset of user's permissions" do
      multi_perm_user = user_with_permissions("ai.agents.read", "ai.agents.create", account: account)
      multi_headers = auth_headers_for(multi_perm_user)

      post path,
           params: { name: "Limited Token", permissions: ["ai.agents.read"] }.to_json,
           headers: multi_headers

      expect_success_response
      data = json_response_data
      expect(data["permissions"]).to eq(["ai.agents.read"])
    end

    it "rejects unauthorized permissions with 403" do
      post path,
           params: { name: "Bad Token", permissions: ["billing.manage"] }.to_json,
           headers: headers

      expect_error_response("Unauthorized permissions", :forbidden)
    end

    it "requires ai.agents.read permission" do
      user_no_perm = user_with_permissions(account: account)
      post path,
           params: { name: "Token" }.to_json,
           headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      post path,
           params: { name: "Token" }.to_json,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ===========================================================================
  # DELETE /api/v1/mcp/tokens/:id
  # ===========================================================================
  describe "DELETE /api/v1/mcp/tokens/:id" do
    it "revokes a token" do
      result = UserToken.create_token_for_user(user, type: "mcp", name: "To Revoke")
      token_record = result[:user_token]

      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: headers

      expect_success_response
      data = json_response_data
      expect(data["revoked"]).to be true
    end

    it "returns the token id and revoked status" do
      result = UserToken.create_token_for_user(user, type: "mcp", name: "To Revoke")
      token_record = result[:user_token]

      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: headers

      expect_success_response
      data = json_response_data
      expect(data["id"]).to eq(token_record.id)
      expect(data["revoked"]).to be true
    end

    it "token no longer appears in active list after revocation" do
      result = UserToken.create_token_for_user(user, type: "mcp", name: "To Revoke")
      token_record = result[:user_token]

      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: headers
      expect(response).to have_http_status(:success)

      expect(token_record.reload.revoked).to be true
    end

    it "cannot revoke another user's token (404)" do
      other_user = create(:user, account: account)
      result = UserToken.create_token_for_user(other_user, type: "mcp", name: "Other User Token")
      token_record = result[:user_token]

      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "requires ai.agents.read permission" do
      result = UserToken.create_token_for_user(user, type: "mcp", name: "Token")
      token_record = result[:user_token]

      user_no_perm = user_with_permissions(account: account)
      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: auth_headers_for(user_no_perm)

      expect(response).to have_http_status(:forbidden)
    end

    it "requires authentication" do
      result = UserToken.create_token_for_user(user, type: "mcp", name: "Token")
      token_record = result[:user_token]

      delete "/api/v1/mcp/tokens/#{token_record.id}", headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
